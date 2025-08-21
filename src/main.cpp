#include <print>
#include "Pipeline.hpp"
#include "Application.hpp"
#include <glm/glm.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <imgui.h>

constexpr uint32_t WIDTH  = 1280;
constexpr uint32_t HEIGHT = 720;


int main()
{
    Application app(WIDTH, HEIGHT, 60);
    PipelineCreateInfo ci = {};
    ci.type               = PipelineType::COMPUTE;
    ci.stages             = VK_SHADER_STAGE_COMPUTE_BIT;
    Pipeline p("shaders/main.slang", ci);

    std::vector<float> color = {0.0f, 1.0f, 0.0f, 1.0f};

    Image background = Image::CubemapFromFile("resources/milky_way_cubemap");

    float distance   = 30.f;
    float orbitAngle = 0.f;

    int32_t simNumSteps = 1e4;
    float simStepSize   = 1e-2;

    Shader& shader = p.GetShader(0);

    app.EnqueueRenderCommand([&](CommandBuffer& cb, Image& frameBuffer, uint32_t frameIndex, float dt)
                             {

             ImGui::PushItemWidth(ImGui::GetFontSize() * 6);
             ImGui::SeparatorText("Camera configuration");
             ImGui::DragFloat("Orbit angle", &orbitAngle, 1.f, -180.f, 180.f);
             ImGui::DragFloat("Camera distance", &distance, 0.5f, 1.f, 100.f);
             ImGui::SeparatorText("Simulation configuration");
             ImGui::DragInt("Number of simulation step", &simNumSteps, 100, 0, 1e6);
             ImGui::DragFloat("Simulation step size", &simStepSize, 0.001f, 1e-6, 1.f);
             ImGui::PopItemWidth();

             shader.SetParameter(frameIndex, "camera.vFOVRadians", glm::radians(60.f));
             shader.SetParameter(frameIndex, "camera.aspectRatio", WIDTH / (float)HEIGHT);
             shader.SetParameter(frameIndex, "camera.angle", glm::radians(orbitAngle));
             shader.SetParameter(frameIndex, "camera.distance", distance);

             shader.SetParameter(frameIndex, "bh.M", 1.f);

             shader.SetParameter(frameIndex, "simParams.numSteps", simNumSteps);
             shader.SetParameter(frameIndex, "simParams.stepSize", simStepSize);

             shader.SetParameter(frameIndex, "screenSize", glm::vec2(WIDTH, HEIGHT));
             shader.SetParameter(frameIndex, "OutputTexture", &frameBuffer);
             shader.SetParameter(frameIndex, "Background", &background);
             p.Bind(cb, frameIndex);

             vkCmdDispatch(cb.GetCommandBuffer(), (WIDTH + 15) / 16, (HEIGHT + 15) / 16, 1); });
    app.Run();
    std::println("Hello world!");
}
