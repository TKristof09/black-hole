#define HALF_PI 1.5707963267948966192313216916398
#define PI 3.1415926535897932384626433832795
#define TWO_PI 6.283185307179586476925286766559

#define NUM_OCTAVES 6


RWTexture2D<float4> OutputTexture;
RWTexture2D<float4> PauseTexture;
RWTexture2D<float4> DebugTexture;
SamplerCube Background;
struct Camera
{
    float vFOVRadians;
    float aspectRatio;
    float3 angle;
    float distance;
}

struct BlackholeParams
{
    float M;
    bool shouldRenderAccretionDisk;
    float2 accretionDisk;
    float accretionDiskHeight;
    double temperatureConstant;
    double temperatureScalar;
    float brightnessScalar;
}

struct SimulationParams
{
    float time;

    int numSteps;
    float stepSize;
    Sampler1D temperatureLUT;
    float2 temperatureBounds;
    bool doFrequencyShift;

    bool doToneMapping;

    float beamExponent;
}

struct DebugParams
{
    bool eventHorizonGrid;
    bool showAccretionDiskSides;
    bool useSimpleDisk;
}

struct NoiseParams 
{

    float twist_strength;
    float scale;
    float rotation_speed;

    float time_mult1;
    float time_mult2;

    float black_level;

    float fade_in_start;
    float fade_in_end;
    float fade_out_start; 
    float fade_out_end;
}

uniform Camera camera;
uniform float2 screenSize;
uniform BlackholeParams bh;
uniform SimulationParams simParams;
uniform DebugParams debug;
uniform NoiseParams noiseParams;

float Hash(float2 p, float t)
{
    float3 p3 = float3(p, t);
    p3  = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}
float Noise(float2 p, float t)
{
    float4 b = float4(floor(p), ceil(p));
    float2 f = smoothstep(0.0, 1.0, fract(p));
    return lerp(lerp(Hash(b.xy, t), Hash(b.zy, t), f.x), lerp(Hash(b.xw, t), Hash(b.zw, t), f.x), f.y);
}

float FBM(float2 pos)
{
    float value = 0.0;
    float scale = 1.0;
    float atten = 0.5;
    for(int i = 0; i < NUM_OCTAVES; i++)
    {
        value += Noise(pos*scale, float(i))*atten;
        scale *= 2.0;
        atten *= 0.6;
    }
    return value;
}

float SampleDiskNoise(float2 polar)
{

    float radius = (polar.x - bh.accretionDisk.x) / (bh.accretionDisk.y - bh.accretionDisk.x);


    float twisted_angle = polar.y + radius * noiseParams.twist_strength; 

    float2 uv;
    uv.x = cos(twisted_angle) * radius;
    uv.y = sin(twisted_angle) * radius;
    uv *= noiseParams.scale;

    // We create two layers of FBM and move them at different speeds and rotations.
    // This makes it look more dynamic, kind of like spiraling/flowing
    float angle_anim = simParams.time * noiseParams.rotation_speed * -1.0; // -1 to align with the direction of the frequency shift
    float2x2 rotation_matrix = float2x2(cos(angle_anim), sin(angle_anim),
                                -sin(angle_anim), cos(angle_anim));

    float fbm1 = FBM(mul(rotation_matrix, uv + float2(simParams.time * 0.1 * noiseParams.time_mult1, simParams.time * 0.05 * noiseParams.time_mult1)));
    float fbm2 = FBM(mul(rotation_matrix, uv * 0.8 + float2(simParams.time * -0.07 * noiseParams.time_mult2, 0.0)));
    float noise_value = fbm1 * fbm2;

    // Increate contrast
    noise_value = (noise_value + 1.0) * 0.5;
    noise_value = smoothstep(noiseParams.black_level, 1.0, noise_value);
    
    // Fade the inside and the outside of the disk
    float fade_in = smoothstep(noiseParams.fade_in_start, noiseParams.fade_in_end, radius);
    float fade_out = smoothstep(noiseParams.fade_out_end, noiseParams.fade_out_start, radius);
    float fade_multiplier = fade_in * fade_out;
    
    noise_value *= fade_multiplier;

    return noise_value;
}

float3 GetRayDir(float2 uv)
{
    float viewPortHeight = 2.0f * tan(camera.vFOVRadians * 0.5f);
    float viewPortWidth  = camera.aspectRatio * viewPortHeight;

    // we consider camera fixed for the simulation on the +x axis facing the origin
    float3 forward = float3(-1, 0, 0);
    float3 right   = float3(0, 0, 1);
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
    n = normalize(n);
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

float4 RK4(float4 state, float2 constants)
{
    float h = simParams.stepSize;
    float4 k1 = CalcDerivatives(state, constants);
    float4 k2 = CalcDerivatives(state + 0.5 * h * k1, constants);
    float4 k3 = CalcDerivatives(state + 0.5 * h * k2, constants);
    float4 k4 = CalcDerivatives(state + h * k3, constants);

    return state + (h / 6.0) * (k1 + k2 * 2.0 + k3 * 2.0 + k4);
}

double GetDiskTemperature(float r)
{
    double radial = max((1.0 - sqrt(bh.accretionDisk.x / r)) / (r * r * r), 0.0001);
    double t4 = bh.temperatureConstant * radial;

    return sqrt(sqrt(t4));
}

float4 TemperatureToColor(float T)
{
    float u = (T - simParams.temperatureBounds.x) / (simParams.temperatureBounds.y - simParams.temperatureBounds.x);
    u = saturate(u);
    return simParams.temperatureLUT.SampleLevel(u, 0);
}

float CalcFrequencyShift(float r, float2 constants)
{
    float gamma = 1.0 / sqrt(1 - 3 * bh.M / r);
    float E = constants.x;
    float L = constants.y;
    float g = 1.0 / (gamma * (1 - L / E * sqrt(bh.M / (r * r * r))));

    return g;
}


float4 SampleAccretionDisk(int2 coord, float4 state, float2 constants, float3 worldPosCartesian)
{

    float4 color;
    if(!debug.showAccretionDiskSides)
    {
        float r = state.y;
        float phi = state.w;

        float t = (float)GetDiskTemperature(r);
        float spectrumShift = simParams.doFrequencyShift ? CalcFrequencyShift(r, constants) : 1.0;
        t = spectrumShift * t;
        float4 hue = TemperatureToColor(t * (float)bh.temperatureScalar);

        // TODO: figure out how to best scale brightness by T^4 according to the Stefan-Boltzmann law
        // float radial = max((1.0 - sqrt(bh.accretionDisk.x / r)) / (r * r * r), 0.0001) * spectrumShift;
        // float brightness = max(bh.brightnessScalar, pow(radial * simParams.beamExponent, 3.0));
        // color = hue * brightness;
        phi = CartesianToPolar(worldPosCartesian).z;
        float noise = debug.useSimpleDisk ? 1.0 : SampleDiskNoise(float2(r, phi));
        color = hue;
        color *= noise;
        // color *= bh.brightnessScalar;
        color *= max(bh.brightnessScalar, pow(spectrumShift, simParams.beamExponent));
        // color *= brightness;
        color.a = pow(noise, 0.5);
        // DebugTexture[coord] = float4(noise, DebugTexture[coord].y, constants.y, spectrumShift);
    }
    else
    {
        if(worldPosCartesian.y < 0)
        {
            color = float4(0.5,0.1,0,1);
        }
        else
        {
            color = float4(0.5,0.5,0,1);
        }
    }

    return color;
}
float4 ToneMap(float4 color)
{
    return simParams.doToneMapping ? color / (color + 1.0) : color;
}
#define OUTPUT(color) {\
        float4 finalColor = ToneMap(color);\
        OutputTexture[int2(DTid.xy)] = finalColor;\
        PauseTexture[int2(DTid.xy)] = finalColor;\
    }

[shader("compute")]
[numthreads(16,16,1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if(DTid.x > screenSize.x || DTid.y > screenSize.y)
        return;

    float2 uv = (DTid.xy + 0.5) / screenSize;

    float4 color = float4(0.0);

    float3 dir = GetRayDir(uv);
    // Rotate the coordinates around the z axis so that the ray lies in the equatorial plane theta = pi / 2
    // We do the simulating while pretending that the camera is positioned always on the +x axis. 
    // We only take into account camera rotation when sampling the background at the end,
    // this way I don't have to deal with any complex rotations for the simulation and the end result should be the same
    
    // Using the constants that are calculated after rotation leads to errors in the doppler shift calculations, so we also calculate the constants before rotation and use those for the doppler.
    // There is probably a better way to do this but this works
    float2 unrotatedConstants;
    {

        const float r0 = camera.distance;
        const float phi0 = 0; // camera always considered to be on +x axis, we do rotation at the end

        // define axis of the local (cartesian) coordinate space near the camera. this is a locally flat space
        float3 e_r = {cos(phi0), 0, sin(phi0)};
        float3 e_theta = {0, 1, 0};
        float3 e_phi = {-sin(phi0), 0, cos(phi0)};

        // project direction into the camera local coordinate system
        float n_r = dot(dir, e_r);
        float n_theta = dot(dir, e_theta);
        float n_phi = dot(dir, e_phi);
        float4 momentum = CalculateTetradMomentum(float3(n_r, n_theta, n_phi));
        float3 psp = momentum.yzw;
        float plen = length(psp);
        if(plen > 0.0) momentum.yzw = psp * (momentum.x / plen); // now -E^2 + |p|^2 == 0

        float r = camera.distance;
        float E = (1 - 2 * bh.M / r) * momentum.x;
        float L = r * r * momentum.w;
        unrotatedConstants = CalculateConstants(momentum);

    }
    float alpha = 0.0; 
    float3x3 rot;
    if (sqrt(dir.y*dir.y + dir.z*dir.z) < 1e-8) 
    {
        rot = float3x3(
                1.0, 0.0, 0.0,
                0.0, 1.0, 0.0,
                0.0, 0.0, 1.0
            );
    } 
    else 
    {
        float alpha = -atan2(dir.y, dir.z);   
        if (alpha >  PI*0.5) alpha -= PI;          // fold into [-PI/2, PI/2]
        else if (alpha < -PI*0.5) alpha += PI;
        rot = GetRotationMatrix(alpha, float3(1,0,0));
    }
    float3x3 cameraRot = 
        mul(GetRotationMatrix(camera.angle.y, float3(0, 1, 0)),
        mul(GetRotationMatrix(camera.angle.x, float3(1, 0, 0)),
            GetRotationMatrix(camera.angle.z, float3(0, 0, 1))));
    float3x3 combined_rot = mul(cameraRot, transpose(rot));
    dir = mul(rot, dir);

    const float r0 = camera.distance;
    const float phi0 = 0; // camera always considered to be on +x axis, we do rotation at the end

    // define axis of the local (cartesian) coordinate space near the camera. this is a locally flat space
    float3 e_r = {cos(phi0), 0, sin(phi0)};
    float3 e_theta = {0, 1, 0};
    float3 e_phi = {-sin(phi0), 0, cos(phi0)};

    // project direction into the camera local coordinate system
    float n_r = dot(dir, e_r);
    float n_theta = dot(dir, e_theta);
    float n_phi = dot(dir, e_phi);

    float4 momentum = CalculateTetradMomentum(float3(n_r, n_theta, n_phi));
    float E = momentum.x;
    float3 psp = momentum.yzw;
    float plen = length(psp);
    if(plen > 0.0) momentum.yzw = psp * (E / plen); // now -E^2 + |p|^2 == 0
    float2 constants = CalculateConstants(momentum);

    // state = (t, r, pr, phi)
    float4 state =
        { 0, 
          r0,     
          momentum.y,
          phi0};
    float3 pvec = momentum.yzw; // spatial in tetrad
    float nullness = -momentum.x*momentum.x + dot(pvec,pvec);


    float3 lastHit = float3(0.0);
    // float numHits = 0;

    for(int i = 0; i < simParams.numSteps; i++)
    {
        state = RK4(state, constants);

        // TODO: fix alpha blending
        if(bh.shouldRenderAccretionDisk && color.a < 0.4)
        {
            float3 worldPosCartesian = mul(combined_rot, PolarToCartesian(float3(state.y, HALF_PI, state.w)));

            bool canHit = length(lastHit) == 0.0 ? true : distance(worldPosCartesian, lastHit) > 1.5 * bh.accretionDisk.x;
            if(canHit && abs(worldPosCartesian.y) <= bh.accretionDiskHeight && bh.accretionDisk.x * bh.M <= state.y && state.y <= bh.accretionDisk.y * bh.M)
            {

                lastHit = worldPosCartesian;
                float4 disk_color = SampleAccretionDisk(int2(DTid.xy), state, unrotatedConstants, worldPosCartesian);
                // numHits += 1.0;
                // DebugTexture[int2(DTid.xy)].y = numHits;
                float alpha = color.a + disk_color.a * (1 - color.a);
                color.rgb = (color.rgb * color.a + disk_color.rgb * disk_color.a * (1 - color.a)) / alpha;
                color.a = alpha;

            }
        }

        if(state.y <= 2 * bh.M)
        {
            if(debug.eventHorizonGrid)
            {
                float3 coords = CartesianToPolar(normalize(mul(combined_rot, PolarToCartesian(float3(state.y, HALF_PI, state.w)))));

                float u = (coords.z + PI) / TWO_PI;
                float v = coords.y / PI;
                float density = 10;
                u *= density;
                v *= density;

                // Create the checkerboard pattern
                float checker = (floor(u) + floor(v));

                if (fmod(checker, 2.0) < 1.0){
                    color.rgb = lerp(float3(0,1,0), color.rgb, color.a);
                    color.a = 1.0;
                }
                else
                {
                    color.rgb = lerp(float3(1,0,0), color.rgb, color.a);
                    color.a = 1.0;
                }
            }
            else
            {
                color.rgb = lerp(float3(0,0,0), color.rgb, color.a);
                color.a = 1.0;
            }


            break;
        }



        if(state.y >= max(camera.distance, bh.M * 10)) // ray goes out very far, no need to continue simulating
            break;
    }

    dir = normalize(PolarToCartesian(float3(state.y, HALF_PI, state.w)));

    // Rotate the ray back into the original coordinate system
    // Rotate the final direction to take into account the camera orbit angle
    dir = mul(combined_rot, dir);
    float4 background_color = Background.SampleLevel(dir, 0.0);
    color.rgb = lerp(background_color.rgb, color.rgb, color.a);
    color.a = 1.0;
    OUTPUT(color);
}
