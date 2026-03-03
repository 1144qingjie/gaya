#include <metal_stdlib>
using namespace metal;

// ========== 数据结构 ==========

struct Particle {
    float3 position;
    float3 velocity;
    float size;
    float randomValue;
    float4 color; // rgb + alpha for photo mode
};

struct VertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float alpha;
    float randomValue;
    float dist;  // 距离中心的距离，用于颜色渐变
    float depth;
    float edgeWeight;
    float3 color;
};

struct Uniforms {
    float time;
    float rotationY;
    float rotationZ;
    float audioIntensity;  // 平滑后的音频强度 (0.0 ~ 1.0)
    float3 audioBands;     // 可选三频段包络（low/mid/high）
    float expansion;
    float seedMotionStrength;
    float aspectRatio;
    float scale;
    float screenScale;     // iOS 屏幕缩放因子
    float photoMode;       // 0.0 = seed, 1.0 = photo
    float photoDispersion;
    float photoParticleSize;
    float photoContrast;
    float photoFlowSpeed;
    float photoFlowAmplitude;
    float photoDepthStrength;
    float photoMouseRadius;
    float2 photoMousePosition;
    float photoColorShiftSpeed;
    float photoAudioDance;
    float photoDanceStrength;
    float photoDepthWave;
    float photoZoom;
    float photoStructureRetention;
    float photoMotionStrength;
    float2 photoPadding;
};

// ========== 辅助函数 ==========

// 伪随机函数
float random2D(float2 st) {
    return fract(sin(dot(st, float2(12.9898, 78.233))) * 43758.5453123);
}

// 3D 噪声函数
float noise3D(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float2 base = i.xy;
    
    float n000 = random2D(base + float2(0, 0));
    float n100 = random2D(base + float2(1, 0));
    float n010 = random2D(base + float2(0, 1));
    float n110 = random2D(base + float2(1, 1));
    float n001 = random2D(base + float2(0, 0) + 1.0);
    float n101 = random2D(base + float2(1, 0) + 1.0);
    float n011 = random2D(base + float2(0, 1) + 1.0);
    float n111 = random2D(base + float2(1, 1) + 1.0);
    
    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    
    float nxy0 = mix(nx00, nx10, f.y);
    float nxy1 = mix(nx01, nx11, f.y);
    
    return mix(nxy0, nxy1, f.z);
}

float3 applyContrast(float3 color, float contrast) {
    float3 shifted = (color - 0.5) * contrast + 0.5;
    return clamp(shifted, 0.0, 1.0);
}

float3 hueShift(float3 color, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    float3x3 mat = float3x3(
        float3(0.299 + 0.701 * c + 0.168 * s, 0.587 - 0.587 * c + 0.330 * s, 0.114 - 0.114 * c - 0.497 * s),
        float3(0.299 - 0.299 * c - 0.328 * s, 0.587 + 0.413 * c + 0.035 * s, 0.114 - 0.114 * c + 0.292 * s),
        float3(0.299 - 0.300 * c + 1.250 * s, 0.587 - 0.588 * c - 1.050 * s, 0.114 + 0.886 * c - 0.203 * s)
    );
    return clamp(mat * color, 0.0, 1.0);
}

// ========== 顶点着色器 ==========

vertex VertexOut vertexShader(const device Particle* particles [[buffer(0)]],
                               const device Uniforms* uniforms [[buffer(1)]],
                               uint vid [[vertex_id]]) {
    VertexOut out;

    Particle particle = particles[vid];
    float3 pos = particle.position;
    float aRandom = particle.randomValue;
    float aSize = particle.size;
    float uTime = uniforms->time;
    float uIntensity = uniforms->audioIntensity;
    float uExpansion = uniforms->expansion;
    float uSeedMotionStrength = uniforms->seedMotionStrength;
    float uScale = uniforms->scale;
    float uAspectRatio = uniforms->aspectRatio;
    float uScreenScale = uniforms->screenScale;
    float3 audioBands = uniforms->audioBands;

    float dist = length(pos);
    out.dist = dist;
    out.depth = 0.0;
    out.edgeWeight = 0.0;

    bool isPhoto = uniforms->photoMode > 0.5;
    if (isPhoto) {
        uSeedMotionStrength = 1.0;
    }
    float photoLifecycleAlpha = 1.0;
    float photoEdgeWeight = 0.0;
    float photoDepth = 0.0;

    // ========== 1. 有机呼吸 ==========
    float breathBase = sin(uTime * 0.8) * 0.5 + sin(uTime * 0.3 + aRandom) * 0.3;
    float breath = breathBase * uSeedMotionStrength;
    
    // ========== 2. 液态表面湍流 ==========
    float noiseFreq = 2.0;
    float noiseAmp = (0.15 + (uIntensity * 0.5)) * uSeedMotionStrength;
    float liquid = noise3D(pos * noiseFreq + uTime * 0.5) * noiseAmp;

    // ========== 3. 音频反应尖峰 ==========
    float spike = max(0.0, sin(pos.x * 5.0 + uTime * 2.0) * cos(pos.y * 5.0)) * uIntensity * 1.2 * uSeedMotionStrength;
    
    // ========== 4. 扩张因子 ==========
    float expansionFactor = 1.0 + (uExpansion * 0.8) + (breath * 0.08);

    // ========== 5. 位移计算 ==========
    float3 displacedPos = pos;
    if (!isPhoto) {
        displacedPos = pos * expansionFactor + (normalize(pos) * (liquid + spike));
    } else {
        // ========== Photo: reuse seed motion model to keep visual language unified ==========
        float stability = clamp(particle.velocity.x, 0.0, 1.0);
        photoEdgeWeight = clamp(particle.velocity.y, 0.0, 1.0);
        float structureRetention = clamp(uniforms->photoStructureRetention, 0.0, 1.0);
        float motionStrength = clamp(uniforms->photoMotionStrength, 0.0, 1.0);
        float structureDamper = 1.0 - structureRetention;
        float audioEnvelope = clamp(dot(audioBands, float3(0.52, 0.33, 0.15)), 0.0, 1.0);
        float dance = uniforms->photoAudioDance * uniforms->photoDanceStrength * audioEnvelope;

        float3 photoBase = pos;
        photoBase.z *= max(uniforms->photoDepthStrength, 0.05);
        float photoDist = length(photoBase);
        float3 photoDir = normalize(photoBase + float3(1e-4));

        float photoBreath = sin(uTime * 0.8) * 0.5 + sin(uTime * 0.3 + aRandom) * 0.3;
        float photoIntensity = uIntensity * (1.0 + dance * (0.45 + structureDamper * 0.55));
        float photoNoiseAmp = 0.15 + (photoIntensity * 0.5);
        float photoLiquid = noise3D(photoBase * 2.0 + uTime * 0.5) * photoNoiseAmp;
        float photoSpike = max(0.0, sin(photoBase.x * 5.0 + uTime * 2.0) * cos(photoBase.y * 5.0))
            * photoIntensity * 1.2;
        float photoExpansion = 1.0 + (uExpansion * 0.8) + (photoBreath * 0.08);
        float3 seedMotionPos = photoBase * photoExpansion + (photoDir * (photoLiquid + photoSpike));
        float motionMix = motionStrength * (0.18 + structureDamper * 0.92);
        motionMix += structureDamper * photoEdgeWeight * 0.22;
        motionMix = clamp(motionMix, 0.02, 1.0);
        displacedPos = mix(photoBase, seedMotionPos, motionMix);

        float depthWave = sin(
            uTime * (1.2 + uniforms->photoFlowSpeed * 0.2) +
            aRandom * 11.0 +
            photoDist * 9.0
        ) * uniforms->photoDepthWave * (0.08 + structureDamper * (0.92 + photoEdgeWeight * 0.6));
        displacedPos += photoDir * depthWave;

        float dispersion = uniforms->photoDispersion * (0.2 + structureDamper * (1.2 + photoEdgeWeight * 0.9));
        displacedPos += photoDir * dispersion;
        photoDepth = displacedPos.z;

        float trailAngle = particle.velocity.z * 6.28318530718 - 3.14159265359;
        float2 trailDir = float2(cos(trailAngle), sin(trailAngle));
        float edgeTrail = smoothstep(0.18, 1.0, photoEdgeWeight);
        float trailPulse = 0.5 + 0.5 * sin(uTime * (1.3 + motionStrength * 0.8) + aRandom * 16.0);
        float trailDrift = edgeTrail * structureDamper * (0.004 + trailPulse * 0.016);
        float2 tangentDir = float2(-trailDir.y, trailDir.x);
        displacedPos.xy += trailDir * trailDrift;
        displacedPos.xy += tangentDir * ((aRandom - 0.5) * edgeTrail * 0.008);

        float shimmerAlpha = 0.92 + 0.08 * sin(uTime * 2.0 + aRandom * 50.0);
        photoLifecycleAlpha = clamp(
            shimmerAlpha * mix(0.96, 1.02, photoEdgeWeight) * (0.84 + 0.16 * stability),
            0.62,
            1.06
        );
    }

    // ========== 6. 外围粒子漂浮 ==========
    // 在调整后的坐标系中，dist > 0.24 相当于原来的 dist > 1.2
    if (!isPhoto && dist > 0.24) {
        displacedPos.y += sin(uTime * 0.5 + aRandom * 10.0) * 0.02 * uSeedMotionStrength;
        displacedPos.x += cos(uTime * 0.3 + aRandom * 10.0) * 0.02 * uSeedMotionStrength;
    }

    // ========== 旋转变换 ==========
    float3 rotatedPos = displacedPos;
    if (!isPhoto) {
        float cosY = cos(uniforms->rotationY);
        float sinY = sin(uniforms->rotationY);
        float cosZ = cos(uniforms->rotationZ);
        float sinZ = sin(uniforms->rotationZ);

        // 绕 Y 轴旋转
        rotatedPos.x = displacedPos.x * cosY - displacedPos.z * sinY;
        rotatedPos.y = displacedPos.y;
        rotatedPos.z = displacedPos.x * sinY + displacedPos.z * cosY;

        // 绕 Z 轴旋转
        float tempX = rotatedPos.x * cosZ - rotatedPos.y * sinZ;
        rotatedPos.y = rotatedPos.x * sinZ + rotatedPos.y * cosZ;
        rotatedPos.x = tempX;
    }

    // ========== 缩放和宽高比校正（iOS 适配）==========
    float3 scaledPos = rotatedPos * uScale;
    if (isPhoto) {
        scaledPos *= max(uniforms->photoZoom, 0.5);
    }
    
    // 宽高比校正：确保粒子球体在任何屏幕上都是圆的
    // 此时 uniforms->aspectRatio 传入的是 (height / width)：
    // - 竖屏：height > width，aspectRatio > 1，需要把 X 放大一些
    // - 横屏：height < width，aspectRatio < 1，需要把 X 缩小一些
    // 统一只对 X 方向做缩放即可完成圆形校正。
    scaledPos.x *= uAspectRatio;

    if (isPhoto && uniforms->photoMouseRadius > 0.0) {
        float2 mouse = uniforms->photoMousePosition;
        // 与上面的宽高比校正保持一致，只对 X 做缩放，保证触摸位置与粒子位置对齐
        mouse.x *= uAspectRatio;
        float2 delta = scaledPos.xy - mouse;
        float d = length(delta);
        float radius = uniforms->photoMouseRadius;
        if (d < radius) {
            float strength = (1.0 - (d / radius));
            float edgeBoost = 0.35 + photoEdgeWeight * 0.95;
            float2 push = normalize(delta + float2(1e-4)) * (0.072 * strength * edgeBoost);
            scaledPos.xy += push;
            scaledPos.z += strength * (0.011 + photoEdgeWeight * 0.03);
        }
    }

    if (isPhoto) {
        // 简单透视投影，强化前后层次
        float perspective = 1.25 / max(0.45, 1.25 - scaledPos.z);
        perspective = clamp(perspective, 0.7, 1.8);
        float perspectiveMix = (1.0 - clamp(uniforms->photoStructureRetention, 0.0, 1.0)) * 0.55;
        scaledPos.xy = mix(scaledPos.xy, scaledPos.xy * perspective, perspectiveMix);
    }

    // Metal NDC: X,Y 范围 [-1, 1]
    out.position = float4(scaledPos.x, scaledPos.y, clamp(0.5 + scaledPos.z * 0.15, 0.0, 1.0), 1.0);

    // ========== 粒子大小（iOS 屏幕适配）==========
    // 基础大小 + 音频响应
    // 参考代码: aSize * (70.0 + uIntensity * 80.0)
    // iOS 适配：考虑屏幕像素密度
    float baseSize = aSize;
    if (!isPhoto) {
        baseSize = aSize * (12.0 + uIntensity * 15.0);
        // 根据屏幕密度调整
        baseSize *= uScreenScale;
        // 根据距离中心的距离微调（核心粒子稍小，外围稍大）
        float distFactor = smoothstep(0.1, 0.5, dist);
        baseSize *= (0.8 + distFactor * 0.4);
    } else {
        float pEdgeWeight = clamp(particle.velocity.y, 0.0, 1.0);
        float audioEnvelope = clamp(dot(audioBands, float3(0.52, 0.33, 0.15)), 0.0, 1.0);
        float dance = uniforms->photoAudioDance * uniforms->photoDanceStrength * audioEnvelope;
        float intensity = uIntensity * (1.0 + dance);
        baseSize = aSize * uniforms->photoParticleSize * (12.0 + intensity * 15.0);
        baseSize *= uScreenScale;
        float distFactor = smoothstep(0.1, 0.5, dist);
        baseSize *= (0.8 + distFactor * 0.4);
        baseSize *= mix(0.92, 1.18, pEdgeWeight);
    }
    
    out.pointSize = max(baseSize, 2.0);

    // ========== 透明度 ==========
    if (!isPhoto) {
        out.alpha = (0.6 + 0.4 * uIntensity) + (0.2 * uSeedMotionStrength * sin(uTime * 2.0 + aRandom * 50.0));
        out.color = float3(0.0);
    } else {
        float alphaPulse = (0.6 + 0.4 * uIntensity) + (0.2 * sin(uTime * 2.0 + aRandom * 50.0));
        out.alpha = particle.color.a * photoLifecycleAlpha * alphaPulse;
        out.color = particle.color.rgb;
        out.depth = photoDepth;
        out.edgeWeight = photoEdgeWeight;
    }

    out.randomValue = aRandom;

    return out;
}

// ========== 片段着色器 ==========

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                float2 pointCoord [[point_coord]],
                                constant Uniforms* uniforms [[buffer(1)]]) {
    float2 uv = pointCoord - float2(0.5);
    float d = length(uv);

    // 圆形裁剪
    if (d > 0.5) {
        discard_fragment();
    }

    bool isPhoto = uniforms->photoMode > 0.5;

    if (isPhoto) {
        // ========== Photo Mode: seed-style glow + photo color ==========
        if (in.alpha < 0.005) {
            discard_fragment();
        }

        float glow = 1.0 - (d * 2.0);
        glow = pow(glow, 1.5);

        float3 color = applyContrast(in.color, uniforms->photoContrast);
        float colorPhase = uniforms->time * uniforms->photoColorShiftSpeed * 0.35;
        float3 shifted = hueShift(color, colorPhase + in.randomValue * 2.5);
        color = mix(color, shifted, in.edgeWeight * 0.12);
        color += float3(0.3) * glow * uniforms->audioIntensity;

        float alpha = in.alpha * glow;
        return float4(color, alpha);

    } else {
        // ========== Seed Mode: Original Glow (unchanged) ==========
        float glow = 1.0 - (d * 2.0);
        glow = pow(glow, 1.5);

        float3 colorIdle = float3(0.298, 0.788, 0.941);
        float3 colorActive = float3(0.969, 0.145, 0.522);

        float uIntensity = uniforms->audioIntensity;
        float uTime = uniforms->time;

        float colorMix = uIntensity * 0.8 + sin(uTime + in.randomValue) * 0.1 * uniforms->seedMotionStrength;
        float3 color = mix(colorIdle, colorActive, colorMix);
        color += float3(0.3) * glow * uIntensity;

        float alpha = in.alpha * glow;
        return float4(color, alpha);
    }
}

// ========== 照片粒子化 Compute ==========

struct PhotoParams {
    uint width;
    uint height;
    uint particleCount;
    float2 center;
    float maxRadius;
    float focusRadius;
    float edgeFalloff;
    float targetRadius;
    float depthScale;
    float maskThreshold;
    float centerSize;
    float edgeSize;
    float2 boundsMin;
    float2 boundsMax;
    float cornerRadius;
    float cornerSoftness;
    float maskReliability;
    uint seed;
    uint padding;
};

inline uint hash_uint(uint x) {
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

inline float rand01(uint x) {
    return (float)(hash_uint(x) & 0x00FFFFFFu) / 16777216.0;
}

kernel void photoParticleKernel(texture2d<float, access::sample> colorTex [[texture(0)]],
                                texture2d<float, access::sample> maskTex [[texture(1)]],
                                texture2d<float, access::sample> densityTex [[texture(2)]],
                                texture2d<float, access::sample> edgeTex [[texture(3)]],
                                device Particle* particles [[buffer(0)]],
                                constant PhotoParams& params [[buffer(1)]],
                                uint gid [[thread_position_in_grid]]) {
    if (gid >= params.particleCount) {
        return;
    }

    uint seed = params.seed + gid * 747796405u;
    float r1 = rand01(seed);
    float r2 = rand01(seed ^ 0x68bc21u);
    float r3 = rand01(seed ^ 0x02e5be93u);
    float r4 = rand01(seed ^ 0x9e3779b9u);
    float r5 = rand01(seed ^ 0x85ebca6bu);
    float r6 = rand01(seed ^ 0x517cc1b7u);

    uint x = min((uint)(r1 * (float)params.width), params.width - 1u);
    uint y = min((uint)(r2 * (float)params.height), params.height - 1u);

    float2 uv = (float2((float)x, (float)y) + 0.5) / float2((float)params.width, (float)params.height);

    constexpr sampler samp(filter::linear, address::clamp_to_edge);

    float3 color = colorTex.sample(samp, uv).rgb;
    float luminance = dot(color, float3(0.299, 0.587, 0.114));
    float mask = maskTex.sample(samp, uv).r;
    float density = densityTex.sample(samp, uv).r;
    float edgeFeature = edgeTex.sample(samp, uv).r;
    float maskReliability = clamp(params.maskReliability, 0.0, 1.0);
    float lumaMask = smoothstep(0.06, 0.34, luminance);
    float semanticMask = mix(lumaMask, mask, maskReliability);
    float supportMask = max(semanticMask, density * 0.65);
    float2 boundsHalf = max((params.boundsMax - params.boundsMin) * 0.5, float2(1e-4));
    float2 boundsCenter = (params.boundsMin + params.boundsMax) * 0.5;
    float2 boundsLocal = uv - boundsCenter;
    float roundedRadius = clamp(params.cornerRadius, 0.0, min(boundsHalf.x, boundsHalf.y) - 1e-4);
    float roundedSoftness = max(params.cornerSoftness, 1e-4);
    float2 q = abs(boundsLocal) - (boundsHalf - float2(roundedRadius));
    float roundedOutside = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - roundedRadius;
    float roundedMask = clamp(1.0 - smoothstep(0.0, roundedSoftness, roundedOutside), 0.0, 1.0);
    float shapeContain = max(supportMask, mix(roundedMask, supportMask, maskReliability * 0.88));

    float2 texel = 1.0 / float2((float)params.width, (float)params.height);
    float maskL = maskTex.sample(samp, uv - float2(texel.x, 0.0)).r;
    float maskR = maskTex.sample(samp, uv + float2(texel.x, 0.0)).r;
    float maskU = maskTex.sample(samp, uv - float2(0.0, texel.y)).r;
    float maskD = maskTex.sample(samp, uv + float2(0.0, texel.y)).r;
    float2 inwardGrad = float2(maskR - maskL, maskD - maskU);
    float gradLen = length(inwardGrad);

    // Reject dark background pixels
    if (supportMask < params.maskThreshold && luminance < 0.10) {
        particles[gid].position = float3(0.0);
        particles[gid].velocity = float3(0.0);
        particles[gid].size = 0.0;
        particles[gid].randomValue = r4;
        particles[gid].color = float4(0.0);
        return;
    }
    if (shapeContain < 0.001) {
        particles[gid].position = float3(0.0);
        particles[gid].velocity = float3(0.0);
        particles[gid].size = 0.0;
        particles[gid].randomValue = r4;
        particles[gid].color = float4(0.0);
        return;
    }

    // ====== Density / Edge / Stability ======
    float2 centered = uv - params.center;
    float maxR = max(params.maxRadius, 1e-4);
    float radial = clamp(length(centered) / maxR, 0.0, 1.0);
    float centerFocus = pow(clamp(1.0 - radial, 0.0, 1.0), 0.55);

    float ratio = clamp(params.edgeFalloff, 2.5, 3.5); // center/edge density ratio target
    float edgeDensityFloor = 1.0 / ratio;
    float centerDensity = edgeDensityFloor + (1.0 - edgeDensityFloor) * pow(1.0 - radial, 0.9);
    centerDensity *= (0.35 + 0.65 * supportMask);
    centerDensity = clamp(centerDensity, 0.0, 1.0);

    float densityWeight = clamp(mix(centerDensity, density, 0.78), 0.0, 1.0);
    float edgeWeight = pow(clamp(edgeFeature, 0.0, 1.0), 0.82);
    float edgeDissolve = smoothstep(0.18, 0.92, edgeWeight);

    float stability = 1.0 - edgeWeight * (0.82 + (1.0 - densityWeight) * 0.38);
    stability *= (0.78 + 0.22 * supportMask);
    stability = clamp(stability, 0.05, 0.99);

    // ====== Density-based Rejection ======
    float keepProb = 0.06 + pow(max(densityWeight, 1e-4), 1.45) * 0.84;
    keepProb = clamp(keepProb, 0.05, 0.97);
    keepProb = mix(keepProb, min(1.0, keepProb + 0.08), luminance * (0.3 + 0.7 * stability));
    float detailBoost = smoothstep(0.35, 0.85, supportMask);
    keepProb += centerFocus * (0.16 + detailBoost * 0.34);
    keepProb *= mix(0.3, 1.0, supportMask);
    keepProb *= mix(0.45, 1.0, shapeContain);
    keepProb *= mix(1.0, 0.32, edgeDissolve);
    keepProb *= mix(1.0, 0.74, edgeDissolve * (1.0 - supportMask));
    float dissolve = smoothstep(0.05, 0.36, supportMask);
    keepProb *= dissolve;
    keepProb = clamp(keepProb, 0.0, 1.0);

    if (r3 > keepProb) {
        particles[gid].position = float3(0.0);
        particles[gid].velocity = float3(0.0);
        particles[gid].size = 0.0;
        particles[gid].randomValue = r4;
        particles[gid].color = float4(0.0);
        return;
    }

    // ====== Position ======
    float imageAspect = max(0.05, (float)params.width / max(1.0, (float)params.height));
    float2 centeredImage = uv - float2(0.5);
    float layoutBase = params.targetRadius;
    float2 pos2d = float2(
        centeredImage.x * (layoutBase * 2.0),
        centeredImage.y * ((layoutBase / imageAspect) * 2.0)
    );

    // ====== Edge Drift ======
    float2 radialDir = normalize(centeredImage + float2(1e-5));
    float2 contourOutward = gradLen > 1e-5 ? normalize(-inwardGrad) : radialDir;
    float2 tangent = float2(-contourOutward.y, contourOutward.x);
    float trailStrength = edgeDissolve * (0.35 + 0.65 * (1.0 - densityWeight));
    float trailLength = params.targetRadius * trailStrength * (0.05 + pow(r4, 1.7) * 0.22);
    float spreadJitter = params.targetRadius * trailStrength * (r5 - 0.5) * 0.06;
    float tangentSpread = params.targetRadius * trailStrength * (r6 - 0.5) * 0.038;
    pos2d += contourOutward * (trailLength + spreadJitter);
    pos2d += tangent * tangentSpread;

    // ====== Layered depth ======
    float depthFromLuma = (luminance - 0.5) * 0.12;
    float depthFromStability = (stability - 0.5) * 0.10;
    float depthFromEdge = (edgeWeight - 0.5) * 0.12;
    float depthFromNoise = (r5 - 0.5) * 0.08;
    float baseDepth = (depthFromLuma + depthFromStability + depthFromEdge + depthFromNoise)
        * max(params.depthScale, 1.0) * (0.55 + 0.45 * supportMask);

    // ====== Output ======
    // velocity encodes: (stability, edgeWeight, contour angle)
    float pi = 3.14159265359;
    float trailAngle = atan2(contourOutward.y, contourOutward.x);
    float trailPacked = (trailAngle + pi) / (2.0 * pi);
    particles[gid].position = float3(pos2d.x, -pos2d.y, baseDepth);
    particles[gid].velocity = float3(stability, edgeWeight, trailPacked);

    // baseSize: core small/tight, edge slightly larger and livelier
    float size = mix(params.centerSize, params.edgeSize, edgeWeight);
    size *= mix(0.76, 1.0, edgeWeight);
    particles[gid].size = size;

    float alpha = mix(0.42, 0.11, edgeWeight);
    alpha *= (0.65 + 0.35 * supportMask);
    alpha *= (0.7 + 0.3 * stability);
    alpha *= (0.58 + 0.42 * shapeContain);

    particles[gid].randomValue = r4;
    particles[gid].color = float4(color, alpha);
}
