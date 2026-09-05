// Demo fragment effect used to exercise Render2D custom materials.
//
// `params.x` supplies time and `params.yz` the mouse position in normalized
// UV coordinates. SDL3 requires fragment-stage uniform buffers in space3, so
// the binding must remain aligned with Render2D's custom-material setup.

cbuffer Effect : register(b0, space3) { // SDL3 requires fragment uniforms to use space3
    float4 params; // x = time, yz = mouse uv (0..1), w = unused
};

struct VSOutput {
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
    float4 color : TEXCOORD1;
    nointerpolation uint textureIndex : MATERIAL_ID;
};

struct PSOutput {
    float4 color : SV_Target;
};

PSOutput PSMain(VSOutput input) {
    float2 uv = input.uv;
    float t = params.x;
    float2 mouse = params.yz;

    // Distance from the cursor drives a plasma phase offset and ripples.
    float dMouse = length(uv - mouse);
    float phase = dMouse * 12.0 - t * 1.7;

    float v = sin(uv.x * 10.0 + t)
            + sin(uv.y * 10.0 + t * 1.3)
            + sin((uv.x + uv.y) * 10.0 + t * 0.7)
            + sin(phase);
    v *= 0.25;

    // Cool neon palette (magenta / cyan / violet).
    float3 magenta = float3(1.0, 0.0, 1.0);
    float3 cyan = float3(0.0, 1.0, 1.0);
    float3 viol = float3(0.35, 0.1, 0.95);

    float s0 = 0.5 + 0.5 * sin(v * 3.14159);
    float s1 = 0.5 + 0.5 * sin((v + 0.66) * 3.14159);
    float s2 = 0.5 + 0.5 * sin((v + 1.33) * 3.14159);
    float3 col = magenta * s0 + cyan * s1 + viol * s2;

    // Ripple emanating from the mouse cursor.
    float ripple = 0.5 + 0.5 * sin(t * 3.0 - dMouse * 26.0);
    col += viol * ripple * 0.5;

    // Bright core that tracks the cursor.
    col += float3(1.0, 0.9, 1.0) * smoothstep(0.18, 0.0, dMouse) * 0.9;

    // Vignette to pop the center.
    float dCenter = length(uv - 0.5);
    col *= smoothstep(0.95, 0.35, dCenter);

    PSOutput output;
    output.color = float4(col, 1.0);
    return output;
}
