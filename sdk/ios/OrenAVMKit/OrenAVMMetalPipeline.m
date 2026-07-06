#import "OrenAVMMetalPipeline.h"

#if TARGET_OS_IPHONE

BOOL OrenAVMMetalBuildPipelineStates(id<MTLDevice> device,
                                     MTLPixelFormat pixelFormat,
                                     id<MTLRenderPipelineState>* geometryPipelineOut,
                                     id<MTLRenderPipelineState>* textPipelineOut) {
    if (geometryPipelineOut) *geometryPipelineOut = nil;
    if (textPipelineOut) *textPipelineOut = nil;
    if (!device) return NO;

    NSString* source =
        @"#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "struct V { packed_float2 pos; packed_float4 color; };\n"
        "struct O { float4 position [[position]]; float4 color; };\n"
        "struct TV { packed_float2 pos; packed_float2 uv; };\n"
        "struct TO { float4 position [[position]]; float2 uv; };\n"
        "vertex O oren_vertex(uint vid [[vertex_id]], constant V* verts [[buffer(0)]]) {\n"
        "  O o; o.position = float4(float2(verts[vid].pos), 0.0, 1.0); o.color = float4(verts[vid].color); return o;\n"
        "}\n"
        "fragment float4 oren_fragment(O in [[stage_in]]) { return in.color; }\n"
        "vertex TO oren_text_vertex(uint vid [[vertex_id]], constant TV* verts [[buffer(0)]]) {\n"
        "  TO o; o.position = float4(float2(verts[vid].pos), 0.0, 1.0); o.uv = float2(verts[vid].uv); return o;\n"
        "}\n"
        "fragment float4 oren_text_fragment(TO in [[stage_in]], texture2d<float> tex [[texture(0)]], constant float& opacity [[buffer(0)]]) {\n"
        "  constexpr sampler s(address::clamp_to_edge, filter::linear); float4 c = tex.sample(s, in.uv); c.a *= opacity; return c;\n"
        "}\n";

    NSError* error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (!library) return NO;

    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"oren_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"oren_fragment"];
    descriptor.colorAttachments[0].pixelFormat = pixelFormat;
    descriptor.colorAttachments[0].blendingEnabled = YES;
    descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    id<MTLRenderPipelineState> geometryPipeline = [device newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!geometryPipeline) return NO;

    MTLRenderPipelineDescriptor* textDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    textDescriptor.vertexFunction = [library newFunctionWithName:@"oren_text_vertex"];
    textDescriptor.fragmentFunction = [library newFunctionWithName:@"oren_text_fragment"];
    textDescriptor.colorAttachments[0].pixelFormat = pixelFormat;
    textDescriptor.colorAttachments[0].blendingEnabled = YES;
    textDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    textDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    textDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    textDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    id<MTLRenderPipelineState> textPipeline = [device newRenderPipelineStateWithDescriptor:textDescriptor error:&error];
    if (!textPipeline) return NO;

    if (geometryPipelineOut) *geometryPipelineOut = geometryPipeline;
    if (textPipelineOut) *textPipelineOut = textPipeline;
    return YES;
}

#endif
