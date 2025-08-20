#define NUM_STEPS 100000
#define STEP_SIZE 0.001
#define MAX_DISTANCE 1000
#define HALF_PI 1.5707963267948966192313216916398

RWTexture2D<float4> OutputTexture;
SamplerCube Background;
struct Camera
{
    float3 position;
    float vFOVRadians;
    float aspectRatio;
}

struct BlackholeParams
{
    float M;
}

uniform Camera camera;
uniform float2 screenSize;
uniform BlackholeParams bh;

float3 GetRayDir(float2 uv)
{
    float viewPortHeight = 2 * tan(camera.vFOVRadians * 0.5f);
    float viewPortWidth  = camera.aspectRatio * viewPortHeight;

    float3 w = normalize(-camera.position);     // forward to origin
    float3 u = normalize(cross(float3(0,1,0), w));
    float3 v = cross(w, u);

    float3 horizontal = viewPortWidth * u;
    float3 vertical   = viewPortHeight * v;
    float3 lowerLeft  = camera.position + w - horizontal*0.5f - vertical*0.5f;

    float3 pointOnPlane = lowerLeft + uv.x * horizontal + uv.y * vertical;
    return normalize(pointOnPlane - camera.position);
}

float3x3 GetRotationMatrix(float alpha)
{
    float c = cos(alpha);
    float s = sin(alpha);
    return {
        c, s, 0,
       -s, c, 0,
        0, 0, 1
    };
}

float3 CartesianToPolar(float3 dir)
{
    float r = 1; // dir is a unit vector
    float phi = atan2(dir.z, dir.x);
    float theta = acos(dir.y / r);

    return {r, theta, phi};
}

float3 PolarToCartesian(float3 v)
{
    float sin_theta = sin(v.y);
    return {
        v.x * sin_theta * cos(v.z),
        v.x * cos(v.y),
        v.x * sin_theta * sin(v.z)
    };
}

float4 CalculateTetradMomentum(float3 n)
{
    float r = length(camera.position);

    float omega = 1.0;
    float p_t = omega / sqrt(1 - 2 * bh.M/r);
    float p_r = omega * sqrt(1 - 2 * bh.M/r) * n.x;
    float p_th = omega * (1.0/r) * n.y;
    float p_ph = omega * (1.0/(r * 1.0)) * n.z;
    return {p_t, p_r, p_th, p_ph};
}
float2 CalculateConstants(float4 momentum)
{
    float r = length(camera.position);
    float E = (1 - 2 * bh.M / r) * momentum.x;
    float L = r * r * momentum.w;

    return {E, L};
}


// state = (t, r, pr, phi)
float4 CalcDerivatives(float4 state, float2 constants)
{
    const float E = constants.x;
    const float L = constants.y;


    float dt = E * 1.0 / (1.0 - 2.0 * bh.M / state.y);
    float dr = state.z;
    float dp_r = L * L * (state.y - 3.0 * bh.M) / (state.y * state.y * state.y * state.y);
    float dphi = L / (state.y * state.y);

    return {dt, dr, dp_r, dphi};
}



[shader("compute")]
[numthreads(16,16,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if(DTid.x > screenSize.x || DTid.y > screenSize.y)
        return;

    bool bad = false;
    float2 uv = (DTid.xy + 0.5) / screenSize;

    float3 dir = GetRayDir(uv);
    
    // Rotate the coordinates around the z axis so that the ray lies in the equatorial plane theta = pi / 2
    float alpha = atan2(dir.y, dir.x);
    float3x3 rot = GetRotationMatrix(alpha);
    dir = mul(rot, dir);


    float r0 = length(camera.position);
    float phi0 = atan2(camera.position.z, camera.position.x);

    float3 e_r = {cos(phi0), 0, sin(phi0)};
    float3 e_theta = {0, 1, 0};
    float3 e_phi = {-sin(phi0), 0, cos(phi0)};

    float n_r = dot(dir, e_r);
    float n_theta = dot(dir, e_theta);
    float n_phi = dot(dir, e_phi);

    float4 momentum = CalculateTetradMomentum(float3(n_r, n_theta, n_phi));
    float2 constants = CalculateConstants(momentum);

    // state = (t, r, pr, phi)
    float4 state =
        { 0, 
          r0,     
          momentum.y,
          phi0};

    for(int i = 0; i < NUM_STEPS; i++)
    {
        float4 derivatives = CalcDerivatives(state, constants);
        state += derivatives * STEP_SIZE;

        if(state.y <= 2 * bh.M)
        {
            OutputTexture[int2(DTid.xy)] = float4(0,0,0,1);
            return;
        }

        if(state.y >= MAX_DISTANCE)
            break;
    }

    dir = normalize(PolarToCartesian(float3(state.y, HALF_PI, state.w)));

    bad |= abs(dir.y) >= 0.0001;
    if(bad)
    {
        OutputTexture[int2(DTid.xy)] = float4(1.0, 0.0, 1.0, 1.0);
    }
    else{
        // Rotate the ray back into the original coordinate system
        dir = mul(transpose(rot), dir);

        float4 color = Background.SampleLevel(dir, 0.0);
        // color = float4(1,0,0,1);

        OutputTexture[int2(DTid.xy)] = color;
    }
}
