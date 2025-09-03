#include <print>
#include "Pipeline.hpp"
#include "Application.hpp"
#include <glm/glm.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <imgui.h>

constexpr uint32_t WIDTH  = 1280;
constexpr uint32_t HEIGHT = 720;

double CalcTemperatureConsant()
{
    constexpr double G_SI     = 6.67430e-11;
    constexpr double C_SI     = 299792458.0;
    constexpr double SIGMA_SI = 5.670374e-8;
    constexpr double M_SUN_KG = 1.989e30;

    constexpr double M_kg               = 10.0 * M_SUN_KG;
    constexpr double eddington_fraction = 0.1;
    constexpr double M_dot              = eddington_fraction * 1.5e16;

    double res = (3.0 * std::pow(C_SI, 6) * M_dot) / (8.0 * glm::pi<double>() * SIGMA_SI * std::pow(G_SI, 2) * M_kg * M_kg);

    // Log::Info("Constant: {}", res);
    return res;
}

double CalcTemperatureScalar(float r_in, float max_temp, double temperatureConstant)
{
    double r_max  = r_in * 49.0 / 36.0;  // this is where the max of the temperature function is
    double radial = (1.0 - glm::sqrt(r_in / r_max)) / (r_max * r_max * r_max);
    double tmax   = glm::pow(temperatureConstant * r_max, 0.25);

    // Log::Info("R_max = {}", r_max);
    // Log::Info("Max temperature {}", tmax);

    return max_temp / tmax;
}

int main()
{
    Application app(WIDTH, HEIGHT, 60);
    PipelineCreateInfo ci = {};
    ci.type               = PipelineType::COMPUTE;
    ci.stages             = VK_SHADER_STAGE_COMPUTE_BIT;
    Pipeline p("shaders/main.slang", ci);

    Image background = Image::CubemapFromFile("resources/milky_way_cubemap");

    float distance = 30.f;
    glm::vec3 cameraRot(0, 90, 30);

    int32_t simNumSteps   = 2e3;
    float simStepSize     = 5e-2;
    bool doFrequencyShift = true;
    bool doToneMapping    = false;

    bool renderAccretionDisk = true;
    glm::vec2 accretionDisk(6, 16);
    float accretionDiskHeight = 0.1f;
    float maxDiskTemperature  = 9e4;
    float brightnessScalar    = 2;
    float beamExponent        = 1.5;

    bool pause = false;

    bool eventHorizonGrid       = false;
    bool showAccretionDiskSides = false;
    bool useSimpleDisk          = false;


    float twist_strength = 3.0;
    float scale          = 2.5;
    float rotation_speed = 0.2;
    float time_mult1     = 0.2;
    float time_mult2     = 0.4;
    float black_level    = 0.1;
    float fade_in_start  = -0.5;
    float fade_in_end    = -0.4;
    float fade_out_start = 0.6;
    float fade_out_end   = 1.0;

    ImageCreateInfo imgci;
    imgci.format      = VK_FORMAT_B8G8R8A8_UNORM;
    imgci.usage       = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    imgci.aspectFlags = VK_IMAGE_ASPECT_COLOR_BIT;
    imgci.layout      = VK_IMAGE_LAYOUT_GENERAL;
    Image pauseImage(WIDTH, HEIGHT, imgci);

    ImageCreateInfo debug;
    imgci.format      = VK_FORMAT_R32G32B32A32_SFLOAT;
    imgci.usage       = VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    imgci.aspectFlags = VK_IMAGE_ASPECT_COLOR_BIT;
    imgci.layout      = VK_IMAGE_LAYOUT_GENERAL;
    Image debugImage(WIDTH, HEIGHT, imgci);

    Image temperatureLUT       = Image::FromFile("resources/bbr_lut.png", false);
    double temperatureConstant = CalcTemperatureConsant();

    Shader& shader = p.GetShader(0);

    float time = 0.0;
    app.EnqueueRenderCommand([&](CommandBuffer& cb, Image& frameBuffer, uint32_t frameIndex, float dt) {
        if(ImGui::Begin("Options"))
        {
            ImGui::SeparatorText("Misc");
            if(ImGui::Button("Pause"))
                pause = !pause;

            ImGui::Checkbox("Render grid on event horizon", &eventHorizonGrid);
            ImGui::Checkbox("Render accretion disk sides", &showAccretionDiskSides);
            ImGui::Checkbox("Use simple accretion disk", &useSimpleDisk);
            ImGui::Checkbox("Use Reinhard tone mapping", &doToneMapping);


            ImGui::PushItemWidth(ImGui::GetFontSize() * 10);
            ImGui::SeparatorText("Black hole configuration");
            ImGui::Checkbox("Render accretion disk", &renderAccretionDisk);
            ImGui::DragFloat2("Accretion Disk", glm::value_ptr(accretionDisk), 0.1f);
            ImGui::DragFloat("Accretion Disk Height", &accretionDiskHeight, 0.01f, 0.f, 1.f);
            ImGui::DragFloat("Accretion Disk Max Temperature", &maxDiskTemperature, 100.f, 0.f);
            ImGui::DragFloat("Accretion Disk Brightness Scalar", &brightnessScalar, 0.1f, 0.f);
            ImGui::DragFloat("Relativistic beaming exponent", &beamExponent, 0.1f, 0.f);

            ImGui::SeparatorText("Camera configuration");
            ImGui::DragFloat3("Rotation", glm::value_ptr(cameraRot), 1.f, -360.f, 360.f);
            ImGui::DragFloat("Distance", &distance, 0.5f, 1.f, 100.f);

            ImGui::SeparatorText("Simulation configuration");
            ImGui::DragInt("Number of simulation step", &simNumSteps, 100, 0, 1e6);
            ImGui::DragFloat("Simulation step size", &simStepSize, 0.001f, 1e-6, 1.f);
            ImGui::Checkbox("Simulate frequency shitf", &doFrequencyShift);

            if(!useSimpleDisk)
            {
                ImGui::SeparatorText("Noise Parameters");

                ImGui::DragFloat("Twist strength", &twist_strength, 0.1f);
                ImGui::DragFloat("Scale", &scale, 0.1f);
                ImGui::DragFloat("Rotation Speed", &rotation_speed, 0.1f);

                ImGui::DragFloat("Time multiplier 1", &time_mult1, 0.1f);
                ImGui::DragFloat("Time multiplier 2", &time_mult2, 0.1f);

                ImGui::DragFloat("Black level", &black_level, 0.1f, 0.0f, 1.0f);

                ImGui::DragFloat("Fade In Start", &fade_in_start, 0.1f, 0.0f);
                ImGui::DragFloat("Fade In End", &fade_in_end, 0.1f, 0.0f);
                ImGui::DragFloat("Fade Out Start", &fade_out_start, 0.1f, 0.0);
                ImGui::DragFloat("Fade Out End", &fade_out_end, 0.1f, 0.0f);
            }

            ImGui::PopItemWidth();
        }
        ImGui::End();

        if(!pause)
        {
            time                     += 1e-2;
            double temperatureScalar  = CalcTemperatureScalar(accretionDisk.x, maxDiskTemperature, temperatureConstant);

            shader.SetParameter(frameIndex, "camera.vFOVRadians", glm::radians(60.f));
            shader.SetParameter(frameIndex, "camera.aspectRatio", WIDTH / (float)HEIGHT);
            shader.SetParameter(frameIndex, "camera.angle", glm::radians(cameraRot));
            shader.SetParameter(frameIndex, "camera.distance", distance);

            shader.SetParameter(frameIndex, "bh.M", 1.f);
            shader.SetParameter(frameIndex, "bh.shouldRenderAccretionDisk", renderAccretionDisk);
            shader.SetParameter(frameIndex, "bh.accretionDisk", accretionDisk);
            shader.SetParameter(frameIndex, "bh.accretionDiskHeight", accretionDiskHeight);
            shader.SetParameter(frameIndex, "bh.temperatureConstant", temperatureConstant);
            shader.SetParameter(frameIndex, "bh.temperatureScalar", temperatureScalar);
            shader.SetParameter(frameIndex, "bh.brightnessScalar", brightnessScalar);

            shader.SetParameter(frameIndex, "simParams.time", time);
            shader.SetParameter(frameIndex, "simParams.numSteps", simNumSteps);
            shader.SetParameter(frameIndex, "simParams.stepSize", simStepSize);
            shader.SetParameter(frameIndex, "temperatureLUT", &temperatureLUT);
            shader.SetParameter(frameIndex, "simParams.temperatureBounds", glm::vec2(1e3, 40e3));  // from the LUT
            shader.SetParameter(frameIndex, "simParams.doFrequencyShift", doFrequencyShift);
            shader.SetParameter(frameIndex, "simParams.doToneMapping", doToneMapping);
            shader.SetParameter(frameIndex, "simParams.beamExponent", beamExponent);

            shader.SetParameter(frameIndex, "debug.eventHorizonGrid", eventHorizonGrid);
            shader.SetParameter(frameIndex, "debug.showAccretionDiskSides", showAccretionDiskSides);
            shader.SetParameter(frameIndex, "debug.useSimpleDisk", useSimpleDisk);

            shader.SetParameter(frameIndex, "noiseParams.twist_strength", twist_strength);
            shader.SetParameter(frameIndex, "noiseParams.scale", scale);
            shader.SetParameter(frameIndex, "noiseParams.rotation_speed", rotation_speed);

            shader.SetParameter(frameIndex, "noiseParams.time_mult1", time_mult1);
            shader.SetParameter(frameIndex, "noiseParams.time_mult2", time_mult2);
            shader.SetParameter(frameIndex, "noiseParams.black_level", black_level);
            shader.SetParameter(frameIndex, "noiseParams.fade_in_start", fade_in_start);
            shader.SetParameter(frameIndex, "noiseParams.fade_in_end", fade_in_end);
            shader.SetParameter(frameIndex, "noiseParams.fade_out_start", fade_out_start);
            shader.SetParameter(frameIndex, "noiseParams.fade_out_end", fade_out_end);

            shader.SetParameter(frameIndex, "screenSize", glm::vec2(WIDTH, HEIGHT));
            shader.SetParameter(frameIndex, "OutputTexture", &frameBuffer);
            shader.SetParameter(frameIndex, "PauseTexture", &pauseImage);
            shader.SetParameter(frameIndex, "Background", &background);
            shader.SetParameter(frameIndex, "DebugTexture", &debugImage);
            p.Bind(cb, frameIndex);

            vkCmdDispatch(cb.GetCommandBuffer(), (WIDTH + 15) / 16, (HEIGHT + 15) / 16, 1);
        }
        else
        {
            VkImageCopy region                   = {};
            region.dstOffset                     = {0, 0, 0};
            region.srcOffset                     = {0, 0, 0};
            region.extent                        = {WIDTH, HEIGHT, 1};
            region.srcSubresource.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
            region.srcSubresource.mipLevel       = 0;
            region.srcSubresource.baseArrayLayer = 0;
            region.srcSubresource.layerCount     = 1;
            region.dstSubresource.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
            region.dstSubresource.mipLevel       = 0;
            region.dstSubresource.baseArrayLayer = 0;
            region.dstSubresource.layerCount     = 1;
            vkCmdCopyImage(cb.GetCommandBuffer(), pauseImage.GetImage(), pauseImage.GetLayout(), frameBuffer.GetImage(), frameBuffer.GetLayout(), 1, &region);
        }
    });
    app.Run();
}
