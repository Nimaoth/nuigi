// Default vertex and fragment shader pair for Render2D.
//
// The vertex stage applies the frame projection and forwards UV, color, and
// texture selection. The fragment stage samples one of the bound textures and
// outputs premultiplied UI color. Register spaces follow SDL3 GPU conventions;
// keep them synchronized with the bindings created in rendering/render2d.nim.

struct VSInput {
    float2 position : TEXCOORD0;
    float2 uv : TEXCOORD1;
    float4 color : TEXCOORD2;
    uint texture: TEXCOORD3;
};

struct VSOutput {
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD0;
    float4 color : TEXCOORD1;
    nointerpolation uint texture : MATERIAL_ID;
};

struct PSOutput {
    float4 color : SV_Target;
};

cbuffer Context : register(b0, space1) {
    float4x4 mvp;
};

Texture2D u_texture0 : register(t0, space2);
SamplerState u_sampler0 : register(s0, space2);
Texture2D u_texture1 : register(t1, space2);
SamplerState u_sampler1 : register(s1, space2);
Texture2D u_texture2 : register(t2, space2);
SamplerState u_sampler2 : register(s2, space2);

float4 GetOutputColor(float4 rgba)
{
    float4 output;
    output.rgb = rgba.rgb;
    output.a = rgba.a;
    return output;
}

VSOutput VSMain(VSInput input) {
    VSOutput output;
    output.pos = mul(mvp, float4(input.position, 0.0, 1.0));
    output.color = input.color;
    output.uv = input.uv;
    output.texture = input.texture;
    return output;
}

PSOutput PSMain(VSOutput input) {
    PSOutput output;
    float4 texColor;
    // texColor = u_texture0.Sample(u_sampler0, input.uv);
    if (input.texture == 0) {
        texColor = u_texture0.Sample(u_sampler0, input.uv);
    } else if (input.texture == 1) {
        texColor = u_texture1.Sample(u_sampler1, input.uv);
    } else {
        texColor = u_texture2.Sample(u_sampler2, input.uv);
    }
    output.color = GetOutputColor(texColor) * input.color;
    return output;
}
