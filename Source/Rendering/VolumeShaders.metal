#include <metal_stdlib>
using namespace metal;
#include <SceneKit/scn_metal>
#include "shared.metal"

// NodeBuffer, samplers, and utility classes are now in shared.metal

// MARK: - Custom Uniforms (CORRECTED to match Swift VolumeUniforms)

struct VolumeUniforms {
    bool isLightingOn;
    bool isBackwardOn;
    int method;
    int renderingQuality;
    int voxelMinValue;
    int voxelMaxValue;
};

// MARK: - Vertex I/O

struct VertexIn {
    float3 position  [[attribute(SCNVertexSemanticPosition)]];
    float3 normal   [[ attribute(SCNVertexSemanticNormal) ]];
    float4 color [[ attribute(SCNVertexSemanticColor) ]];
    float2 uv [[ attribute(SCNVertexSemanticTexcoord0) ]];
};

struct VertexOut {
    float4 position [[position]];
    float3 localPosition;
    float3 normal;
    float2 uv;
};

struct FragmentOut {
    float4 color [[color(0)]];
};


// Utility classes Unity, Util, and VR are now in shared.metal


// MARK: - Main Vertex Shader

vertex VertexOut volume_vertex(VertexIn in [[ stage_in ]],
                               constant NodeBuffer& scn_node [[ buffer(1) ]])
{
    VertexOut out;
    out.position = Unity::ObjectToClipPos(float4(in.position, 1.0f), scn_node);
    out.uv = in.uv;
    out.normal = Unity::ObjectToWorldNormal(in.normal, scn_node);
    out.localPosition = in.position;
    return out;
}

// MARK: - Fragment Shaders (Rendering Methods)

FragmentOut direct_volume_rendering(VertexOut in,
                                    constant SCNSceneBuffer& scn_frame,
                                    constant NodeBuffer& scn_node,
                                    constant VolumeUniforms& uniforms,
                                     texture3d<float, access::sample> dicom,
                                    texture2d<float, access::sample> transferColor)
{
    FragmentOut out;
    
    VR::RayInfo ray;
    if (uniforms.isBackwardOn)
        ray = VR::getRayBack2Front(in.localPosition, scn_node, scn_frame);
    else
        ray = VR::getRayFront2Back(in.localPosition, scn_node, scn_frame);
    
    VR::RaymarchInfo raymarch = VR::initRayMarch(ray, uniforms.renderingQuality);
    float3 lightDir = normalize(Unity::ObjSpaceViewDir(float4(0.0f), scn_node, scn_frame));
    
    ray.startPosition = ray.startPosition + (2 * ray.direction / raymarch.numSteps);
    
    float4 col = float4(0.0f);
    for (int iStep = 0; iStep < raymarch.numSteps; iStep++)
    {
        const float t = float(iStep) * raymarch.numStepsRecip;
        const float3 currPos = Util::lerp(ray.startPosition, ray.endPosition, t);
        
        if (currPos.x < 0 || currPos.x >= 1 ||
            currPos.y < 0 || currPos.y >= 1 ||
            currPos.z < 0 || currPos.z >= 1)
            break;
        
        float density = dicom.sample(sampler3d, currPos).r; // 0..1 for r8Unorm
        
        float4 src = VR::getTfColour(transferColor, density);
        
        if (uniforms.isLightingOn) {
            float3 gradient = VR::calGradient(dicom, currPos);
            float3 normal = normalize(gradient);
            float3 direction = uniforms.isBackwardOn ? ray.direction : -ray.direction;
            src.rgb = Util::calculateLighting(src.rgb, normal, lightDir, direction, 0.3f);
        }
        
        if (density < 0.1f)
            src.a = 0.0f;
        
        if (uniforms.isBackwardOn)
        {
            col.rgb = src.a * src.rgb + (1.0f - src.a) * col.rgb;
            col.a = src.a + (1.0f - src.a) * col.a;
        }
        else
        {
            src.rgb *= src.a;
            col = (1.0f - col.a) * src + col;
        }
        
        if (col.a > 1)
            break;
    }
    
    out.color = col;
    return out;
}

// MARK: - Surface Rendering (additional method from reference)

FragmentOut surface_rendering(VertexOut in,
                             constant SCNSceneBuffer& scn_frame,
                             constant NodeBuffer& scn_node,
                             constant VolumeUniforms& uniforms,
                              texture3d<float, access::sample> dicom,
                             texture2d<float, access::sample> transferColor)
{
    FragmentOut out;
    
    VR::RayInfo ray = VR::getRayFront2Back(in.localPosition, scn_node, scn_frame);
    VR::RaymarchInfo raymarch = VR::initRayMarch(ray, uniforms.renderingQuality);
    float3 lightDir = normalize(Unity::ObjSpaceViewDir(float4(0.0f), scn_node, scn_frame));
    
    ray.startPosition = ray.startPosition + (2 * ray.direction / raymarch.numSteps);
    
    float4 col = float4(0);
    for (int iStep = 0; iStep < raymarch.numSteps; iStep++)
    {
        const float t = float(iStep) * raymarch.numStepsRecip;
        const float3 currPos = Util::lerp(ray.startPosition, ray.endPosition, t);
        
        if (currPos.x < 0 || currPos.x >= 1 ||
            currPos.y < 0 || currPos.y >= 1 ||
            currPos.z < 0 || currPos.z >= 1)
            continue;
            
        float density = dicom.sample(sampler3d, currPos).r;
        if (density > 0.2)
        {
            float3 gradient = VR::calGradient(dicom, currPos);
            float3 normal = normalize(gradient);
            col = VR::getTfColour(transferColor, density);
            if (uniforms.isLightingOn)
                col.rgb = Util::calculateLighting(col.rgb, normal, lightDir, ray.direction, 0.15f);
            col.a = 1;
            break;
        }
    }
    
    out.color = col;
    return out;
}

// MARK: - Maximum Intensity Projection (additional method from reference)

FragmentOut maximum_intensity_projection(VertexOut in,
                                        constant SCNSceneBuffer& scn_frame,
                                        constant NodeBuffer& scn_node,
                                        constant VolumeUniforms& uniforms,
                                         texture3d<float, access::sample> dicom)
{
    FragmentOut out;
    
    VR::RayInfo ray = VR::getRayBack2Front(in.localPosition, scn_node, scn_frame);
    VR::RaymarchInfo raymarch = VR::initRayMarch(ray, uniforms.renderingQuality);
    
    float maxDensity = 0;
    for (int iStep = 0; iStep < raymarch.numSteps; iStep++)
    {
        const float t = float(iStep) * raymarch.numStepsRecip;
        const float3 currPos = Util::lerp(ray.startPosition, ray.endPosition, t);

        if (currPos.x < -1e-6 || currPos.x >= 1+1e-6 ||
            currPos.y < -1e-6 || currPos.y >= 1+1e-6 ||
            currPos.z < -1e-6 || currPos.z >= 1+1e-6)
            break;

        float density = dicom.sample(sampler3d, currPos).r;
        
        if (density > 0.1f)
            maxDensity = max(maxDensity, density);
    }
    
    out.color = float4(maxDensity);
    return out;
}

// MARK: - Main Fragment Shader (CORRECTED texture binding names)

fragment FragmentOut volume_fragment(VertexOut in [[ stage_in ]],
                                      constant SCNSceneBuffer& scn_frame [[ buffer(0) ]],
                                      constant NodeBuffer& scn_node [[ buffer(1) ]],
                                      constant VolumeUniforms& uniforms [[ buffer(4) ]],
                                       texture3d<float, access::sample> dicom [[ texture(0) ]],
                                      texture2d<float, access::sample> transferColor [[ texture(3) ]])
{
    switch (uniforms.method)
    {
        case 0:
            return surface_rendering(in, scn_frame, scn_node, uniforms, dicom, transferColor);
        case 1:
            return direct_volume_rendering(in, scn_frame, scn_node, uniforms, dicom, transferColor);
        default:
            return maximum_intensity_projection(in, scn_frame, scn_node, uniforms, dicom);
    }
} 