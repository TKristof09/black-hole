#include <print>
#include "Pipeline.hpp"
#include "Application.hpp"
#include "glm/glm.hpp"

int main()
{
    Application app(800, 600, 60);
    PipelineCreateInfo ci = {};
    ci.type               = PipelineType::COMPUTE;
    ci.stages             = VK_SHADER_STAGE_COMPUTE_BIT;
    Pipeline p("shaders/test.slang", ci);

    std::vector<float> color = {0.0f, 1.0f, 0.0f, 1.0f};
    app.EnqueueRenderCommand([&](CommandBuffer& cb, Image& frameBuffer, uint32_t frameIndex, float dt)
                             {
                             p.GetShader(0).SetParameter(frameIndex, "color", color);
                             p.GetShader(0).SetParameter(frameIndex, "output", &frameBuffer);
                             p.Bind(cb, frameIndex);

                             vkCmdDispatch(cb.GetCommandBuffer(), 800 / 16, 800 / 16, 1); });
    app.Run();
    std::println("Hello world!");
}
