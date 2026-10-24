#include <metal_stdlib>
using namespace metal;

// MARK: - Depth map

struct DepthMapUniforms {
    float4x4 displayInverse;
    float4 params; // near, far, unused, unused
};

struct DepthVertexOut {
    float4 position [[position]];
    float2 viewportUV;
};

vertex DepthVertexOut depthMapVertex(uint vertexID [[vertex_id]]) {
    float2 uv = float2(float((vertexID << 1) & 2), float(vertexID & 2));
    float2 ndc = uv * 2.0 - 1.0;

    DepthVertexOut out;
    out.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
    out.viewportUV = uv;
    return out;
}

fragment float4 depthMapFragment(DepthVertexOut in [[stage_in]],
                                 constant DepthMapUniforms &uniforms [[buffer(0)]],
                                 texture2d<float> depthTexture [[texture(0)]],
                                 texture2d<float> paletteTexture [[texture(1)]]) {
    constexpr sampler depthSampler(coord::normalized, filter::nearest, address::clamp_to_edge);
    constexpr sampler paletteSampler(coord::normalized, filter::linear, address::clamp_to_edge);

    float3 imageCoordinate = (uniforms.displayInverse * float4(in.viewportUV, 0.0, 1.0)).xyz;
    float2 imageUV = imageCoordinate.xy;
    float3 background = float3(0.010, 0.014, 0.022);

    if (any(imageUV < 0.0) || any(imageUV > 1.0)) {
        return float4(background, 1.0);
    }

    float depth = depthTexture.sample(depthSampler, imageUV).r;
    if (!isfinite(depth) || depth < 0.01 || depth > uniforms.params.y) {
        return float4(background, 1.0);
    }

    float normalized = clamp((depth - uniforms.params.x) / max(uniforms.params.y - uniforms.params.x, 0.001), 0.0, 1.0);
    float4 color = paletteTexture.sample(paletteSampler, float2(normalized, 0.5));

    // Subtle isolines make distance readable without any photographic detail.
    float contour = fract(depth * 7.0);
    float line = smoothstep(0.965, 1.0, contour) + (1.0 - smoothstep(0.0, 0.035, contour));
    color.rgb = mix(color.rgb, float3(1.0), line * 0.065);

    float2 centered = in.viewportUV - 0.5;
    float vignette = 1.0 - dot(centered, centered) * 0.48;
    color.rgb *= vignette;

    return float4(color.rgb, 1.0);
}

// MARK: - Point cloud

struct PointCloudUniforms {
    float4x4 viewProjection;
    float4x4 cameraTransform;
    float4x4 intrinsics;
    uint4 sizes;  // depth width, depth height, image width, image height
    float4 params; // near, far, point scale, sample step
};

struct PointVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float2 paletteUV;
};

static PointVertexOut culledPoint(void) {
    PointVertexOut out;
    out.position = float4(2.0, 2.0, 2.0, 1.0);
    out.pointSize = 1.0;
    out.paletteUV = float2(0.0);
    return out;
}

vertex PointVertexOut pointCloudVertex(uint vertexID [[vertex_id]],
                                       constant PointCloudUniforms &uniforms [[buffer(0)]],
                                       texture2d<float, access::read> depthTexture [[texture(0)]]) {
    uint depthWidth = uniforms.sizes.x;
    uint depthHeight = uniforms.sizes.y;
    uint step = max(1u, uint(round(uniforms.params.w)));
    uint columns = (depthWidth + step - 1) / step;

    uint px = (vertexID % columns) * step;
    uint py = (vertexID / columns) * step;

    if (px >= depthWidth || py >= depthHeight) {
        return culledPoint();
    }

    float depth = depthTexture.read(uint2(px, py)).r;
    if (!isfinite(depth) || depth < 0.01 || depth > uniforms.params.y) {
        return culledPoint();
    }

    float fx = uniforms.intrinsics[0][0];
    float fy = uniforms.intrinsics[1][1];
    float cx = uniforms.intrinsics[2][0];
    float cy = uniforms.intrinsics[2][1];

    float2 depthSize = float2(float(depthWidth), float(depthHeight));
    float2 imageSize = float2(float(uniforms.sizes.z), float(uniforms.sizes.w));
    float2 imagePixel = (float2(float(px), float(py)) + 0.5) / depthSize * imageSize;

    float cameraX = (imagePixel.x - cx) / fx * depth;
    float cameraY = (cy - imagePixel.y) / fy * depth;

    float4 world = uniforms.cameraTransform * float4(cameraX, cameraY, -depth, 1.0);
    float4 clip = uniforms.viewProjection * world;

    PointVertexOut out;
    out.position = clip;
    float distanceToCamera = max(clip.w, 0.05);
    out.pointSize = clamp(uniforms.params.z * 2.35 / distanceToCamera, 1.0, 7.0);

    float normalized = clamp((depth - uniforms.params.x) / max(uniforms.params.y - uniforms.params.x, 0.001), 0.0, 1.0);
    out.paletteUV = float2(normalized, 0.5);
    return out;
}

fragment float4 pointCloudFragment(PointVertexOut in [[stage_in]],
                                   float2 pointCoordinate [[point_coord]],
                                   texture2d<float> paletteTexture [[texture(0)]]) {
    constexpr sampler paletteSampler(coord::normalized, filter::linear, address::clamp_to_edge);

    float radius = length(pointCoordinate - float2(0.5));
    if (radius > 0.5) {
        discard_fragment();
    }

    float4 color = paletteTexture.sample(paletteSampler, in.paletteUV);
    float alpha = 1.0 - smoothstep(0.30, 0.5, radius);
    float brightness = 0.72 + 0.28 * (1.0 - radius * 2.0);

    return float4(color.rgb * brightness, alpha);
}
