StructuredBuffer<float> buffer0;
StructuredBuffer<float> buffer1;
RWStructuredBuffer<float> result;

RWTexture2D output;
uniform float[4] color;

[shader("compute")]
[numthreads(16,16,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint width, height;
    output.GetDimensions(width, height);

    float2 uv = float2(DTid.xy) / float2(width, height);
    output[DTid.xy] = float4(uv, 0.0, 1.0); // RG = UV, B=0, A=1
    output[DTid.xy].x = color[0];
    output[DTid.xy].y = color[1];
    output[DTid.xy].z = color[2];
    output[DTid.xy].w = color[3];
}

