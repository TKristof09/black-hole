#include <print>
#include "Pipeline.hpp"
#include "Application.hpp"
#include <glm/glm.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <imgui.h>

int main()
{
    Application app(800, 600, 60);
    PipelineCreateInfo ci = {};
    ci.type               = PipelineType::COMPUTE;
    ci.stages             = VK_SHADER_STAGE_COMPUTE_BIT;
    Pipeline p("shaders/main.slang", ci);

    std::vector<float> color = {0.0f, 1.0f, 0.0f, 1.0f};

    Image background = Image::CubemapFromFile("resources/milky_way_cubemap");

    glm::vec3 rot{0.0};
    float distance = 30.f;

    Shader& shader = p.GetShader(0);

    app.EnqueueRenderCommand([&](CommandBuffer& cb, Image& frameBuffer, uint32_t frameIndex, float dt)
                             {
             ImGui::DragFloat3("Rotation", glm::value_ptr(rot), 1.f, -180.f, 180.f);
             ImGui::DragFloat("Camera distance", &distance, 0.5f, 1.f, 100.f);

             float pitch = glm::radians(rot.x);
             float yaw   = glm::radians(rot.y);
             float roll  = glm::radians(rot.z);

             // build rotation: yaw (Y) then pitch (X) then roll (Z)
             glm::mat4 rot(1.0f);
             rot = glm::rotate(rot, yaw,  glm::vec3(0.0f, 1.0f, 0.0f));
             rot = glm::rotate(rot, pitch,glm::vec3(1.0f, 0.0f, 0.0f));
             rot = glm::rotate(rot, roll, glm::vec3(0.0f, 0.0f, 1.0f));

             // camera-space basis vectors (camera looks along -Z)
             glm::vec3 right   = glm::normalize(glm::vec3(rot * glm::vec4(1,0,0,0)));
             glm::vec3 up      = glm::normalize(glm::vec3(rot * glm::vec4(0,1,0,0)));
             glm::vec3 forward = glm::normalize(glm::vec3(rot * glm::vec4(0,0,-1,0))); // -Z

             shader.SetParameter(frameIndex, "camera.position", -forward * distance);
             shader.SetParameter(frameIndex, "camera.vFOVRadians", glm::radians(60.f));
             shader.SetParameter(frameIndex, "camera.aspectRatio", 800.f/600.f);
             shader.SetParameter(frameIndex, "bh.M", 1.f);
             shader.SetParameter(frameIndex, "screenSize", glm::vec2(800, 600));
             shader.SetParameter(frameIndex, "OutputTexture", &frameBuffer);
             shader.SetParameter(frameIndex, "Background", &background);
             p.Bind(cb, frameIndex);

             vkCmdDispatch(cb.GetCommandBuffer(), 800 / 16, 800 / 16, 1); });
    app.Run();
    std::println("Hello world!");
}
