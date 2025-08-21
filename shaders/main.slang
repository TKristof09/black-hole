#define HALF_PI 1.5707963267948966192313216916398

RWTexture2D<float4> OutputTexture;
SamplerCube Background;
struct Camera
{
    float vFOVRadians;
    float aspectRatio;
    float angle;
    float distance;
}

struct BlackholeParams
{
    float M;
}

struct SimulationParams
{
    int numSteps;
    float stepSize;
}
uniform Camera camera;
uniform float2 screenSize;
uniform BlackholeParams bh;
uniform SimulationParams simParams;


float3 GetRayDir(float2 uv)
{
    float viewPortHeight = 2.0f * tan(camera.vFOVRadians * 0.5f);
    float viewPortWidth  = camera.aspectRatio * viewPortHeight;

    // we consider camera fixed for the simulation on the +z axis facing the origin
    float3 forward = float3(0, 0, -1);
    float3 right   = float3(1, 0, 0);
    float3 up      = float3(0, 1, 0);

    float2 screenPos = uv - 0.5f;

    float3 dir = forward + screenPos.x * viewPortWidth * right + screenPos.y * viewPortHeight * up;

    return normalize(dir);
}

float3x3 GetRotationMatrix(float alpha, float3 axis)
{
    float c = cos(alpha);
    float s = sin(alpha);

    float3 temp = (1 - c) * axis;

    return {
        axis.x * temp.x + c,            axis.x * temp.y + axis.z * s,   axis.x * temp.z - axis.y * s,
        axis.x * temp.y - axis.z * s,   axis.y * temp.y + c,            axis.y * temp.z + axis.x * s,
        axis.x * temp.z + axis.y * s,   axis.y * temp.z - axis.x * s,   axis.z * temp.z + c,
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
    float r = camera.distance;

    float omega = 1.0;
    float p_t = omega / sqrt(1 - 2 * bh.M/r);
    float p_r = omega * sqrt(1 - 2 * bh.M/r) * n.x;
    float p_th = omega * (1.0/r) * n.y;
    float p_ph = omega * (1.0/(r * 1.0)) * n.z;
    return {p_t, p_r, p_th, p_ph};
}
float2 CalculateConstants(float4 momentum)
{
    float r = camera.distance;
    float E = (1 - 2 * bh.M / r) * momentum.x;
    float L = r * r * momentum.w;

    return {E, L};
}


// state = (t, r, pr, phi)
float4 CalcDerivatives(float4 state, float2 constants)
{
    const float E = constants.x;
    const float L = constants.y;

    float inv_r = 1.0 / state.y;

    float dt = E * 1.0 / (1.0 - 2.0 * bh.M * inv_r);
    float dr = state.z;
    float dp_r = L * L * (state.y - 3.0 * bh.M) * inv_r * inv_r * inv_r * inv_r;
    float dphi = L * inv_r * inv_r;

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
    // We do the simulating while pretending that the camera is positioned always on the +z axis. 
    // We only take into account camera rotation when sampling the background at the end,
    // this way I don't have to deal with any complex rotations for the simulation and the end result should be the same
    float alpha = atan2(dir.y, dir.x);
    float3x3 rot = GetRotationMatrix(alpha, float3(0,0,1));
    dir = mul(rot, dir);

    bad |= abs(dir.y) >= 0.0001;

    const float r0 = camera.distance;
    const float phi0 = HALF_PI; // camera always considered to be on +z axis, we do rotation at the end

    // define axis of the local (cartesian) coordinate space near the camera. this is a locally flat space
    float3 e_r = {cos(phi0), 0, sin(phi0)};
    float3 e_theta = {0, 1, 0};
    float3 e_phi = {-sin(phi0), 0, cos(phi0)};

    // project direction into the camera local coordinate system
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

    for(int i = 0; i < simParams.numSteps; i++)
    {
        float4 derivatives = CalcDerivatives(state, constants);
        state += derivatives * simParams.stepSize;

        if(state.y <= 2 * bh.M)
        {
            OutputTexture[int2(DTid.xy)] = float4(0,0,0,1);

            if(bad)
            {
                OutputTexture[int2(DTid.xy)] = float4(1.0, 0.0, 1.0, 1.0);
            }
            return;
        }

        if(state.y >= max(camera.distance, bh.M * 10)) // ray goes out very far, no need to continue simulating
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

        // Rotate the final direction to take into account the camera orbit angle
        float3x3 cameraRot = GetRotationMatrix(camera.angle, float3(0, 1, 0));
        dir = mul(cameraRot, dir);
        float4 color = Background.SampleLevel(dir, 0.0);

        OutputTexture[int2(DTid.xy)] = color;
    }
}
