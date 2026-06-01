#import "OrenAVMKit.h"

#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <string.h>

typedef struct {
    float x;
    float y;
    float r;
    float g;
    float b;
    float a;
} OrenAVMMetalVertex;

typedef struct {
    float x;
    float y;
    float u;
    float v;
} OrenAVMMetalTextVertex;

typedef struct {
    BOOL enabled;
    MTLScissorRect rect;
} OrenAVMMetalScissorState;

@interface OrenAVMMetalVertexRun : NSObject
@property(nonatomic, strong) NSData* vertices;
@property(nonatomic) BOOL hasScissor;
@property(nonatomic) MTLScissorRect scissor;
@end

@implementation OrenAVMMetalVertexRun
@end

@interface OrenAVMMetalTextRun : NSObject
@property(nonatomic, strong) id<MTLTexture> texture;
@property(nonatomic, strong) NSData* vertices;
@property(nonatomic) BOOL hasScissor;
@property(nonatomic) MTLScissorRect scissor;
@end

@implementation OrenAVMMetalTextRun
@end

@interface OrenAVMMetalTextResource : NSObject
@property(nonatomic, copy) NSString* text;
@property(nonatomic, copy) NSData* rgba;
@end

@implementation OrenAVMMetalTextResource
@end

@interface OrenAVMMetalImageRun : NSObject
@property(nonatomic, strong) id<MTLTexture> texture;
@property(nonatomic, strong) NSData* vertices;
@property(nonatomic) BOOL hasScissor;
@property(nonatomic) MTLScissorRect scissor;
@end

@implementation OrenAVMMetalImageRun
@end

@interface OrenAVMMetalTextCacheEntry : NSObject
@property(nonatomic, strong) id<MTLTexture> texture;
@property(nonatomic) CGSize logicalSize;
@property(nonatomic) NSUInteger pixelCount;
@end

@implementation OrenAVMMetalTextCacheEntry
@end

static const NSUInteger OrenAVMMetalTextCachePixelLimit = 8u * 1024u * 1024u;
static const NSUInteger OrenAVMMetalTextCacheEntryLimit = 256u;
static const NSUInteger OrenAVMMetalDefaultRetainedImagePixelLimit = 16u * 1024u * 1024u;
static const NSUInteger OrenAVMMetalDefaultRetainedImageCountLimit = 1024u;

static uint16_t OrenAVMMetalReadU16LE(const uint8_t* p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t OrenAVMMetalReadU32LE(const uint8_t* p) {
    return (uint32_t)p[0] |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static uint64_t OrenAVMMetalNowNs(void) {
    return (uint64_t)llround(CACurrentMediaTime() * 1000000000.0);
}

static uint64_t OrenAVMMetalTargetBudgetNs(uint32_t hzMilli) {
    uint64_t effectiveHzMilli = hzMilli == 0 ? 60000ull : (uint64_t)hzMilli;
    return 1000000000000ull / effectiveHzMilli;
}

static BOOL OrenAVMMetalAssignError(NSError** error, NSInteger code, NSString* message) {
    if (error) {
        *error = [NSError errorWithDomain:OrenAVMKitErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message ?: @"OrenAVMMetalView error"}];
    }
    return NO;
}

static MTLScissorRect OrenAVMMetalClipRectToScissor(int64_t x,
                                                    int64_t y,
                                                    uint32_t w,
                                                    uint32_t h,
                                                    uint32_t logicalW,
                                                    uint32_t logicalH,
                                                    uint32_t drawableW,
                                                    uint32_t drawableH) {
    MTLScissorRect r;
    int64_t x0 = x < 0 ? 0 : x;
    int64_t y0 = y < 0 ? 0 : y;
    int64_t x2 = x + (int64_t)w;
    int64_t y2 = y + (int64_t)h;
    if (x2 < 0) x2 = 0;
    if (y2 < 0) y2 = 0;
    r.x = logicalW == 0 ? 0 : (NSUInteger)(((uint64_t)x0 * drawableW) / logicalW);
    r.y = logicalH == 0 ? 0 : (NSUInteger)(((uint64_t)y0 * drawableH) / logicalH);
    NSUInteger x1 = logicalW == 0 ? 0 : (NSUInteger)(((uint64_t)x2 * drawableW) / logicalW);
    NSUInteger y1 = logicalH == 0 ? 0 : (NSUInteger)(((uint64_t)y2 * drawableH) / logicalH);
    if (r.x > drawableW) r.x = drawableW;
    if (r.y > drawableH) r.y = drawableH;
    if (x1 > drawableW) x1 = drawableW;
    if (y1 > drawableH) y1 = drawableH;
    r.width = x1 > r.x ? x1 - r.x : 0;
    r.height = y1 > r.y ? y1 - r.y : 0;
    return r;
}

static MTLScissorRect OrenAVMMetalIntersectScissor(MTLScissorRect a, MTLScissorRect b) {
    NSUInteger x0 = a.x > b.x ? a.x : b.x;
    NSUInteger y0 = a.y > b.y ? a.y : b.y;
    NSUInteger ax1 = a.x + a.width;
    NSUInteger ay1 = a.y + a.height;
    NSUInteger bx1 = b.x + b.width;
    NSUInteger by1 = b.y + b.height;
    NSUInteger x1 = ax1 < bx1 ? ax1 : bx1;
    NSUInteger y1 = ay1 < by1 ? ay1 : by1;
    MTLScissorRect out;
    out.x = x0;
    out.y = y0;
    out.width = x1 > x0 ? x1 - x0 : 0;
    out.height = y1 > y0 ? y1 - y0 : 0;
    return out;
}

static void OrenAVMMetalFlushVertexRun(NSMutableArray<OrenAVMMetalVertexRun*>* runs,
                                       NSMutableData* vertices,
                                       OrenAVMMetalScissorState scissor) {
    if (vertices.length == 0) return;
    OrenAVMMetalVertexRun* run = [[OrenAVMMetalVertexRun alloc] init];
    run.vertices = [vertices copy];
    run.hasScissor = scissor.enabled;
    run.scissor = scissor.rect;
    [runs addObject:run];
    [vertices setLength:0];
}

static float OrenAVMMetalClipX(float x, float logicalWidth) {
    return logicalWidth <= 0.0f ? 0.0f : (x / logicalWidth) * 2.0f - 1.0f;
}

static float OrenAVMMetalClipY(float y, float logicalHeight) {
    return logicalHeight <= 0.0f ? 0.0f : 1.0f - (y / logicalHeight) * 2.0f;
}

static OrenAVMMetalVertex OrenAVMMetalMakeVertex(float x,
                                                float y,
                                                float logicalWidth,
                                                float logicalHeight,
                                                const uint8_t* rgba) {
    OrenAVMMetalVertex v;
    v.x = OrenAVMMetalClipX(x, logicalWidth);
    v.y = OrenAVMMetalClipY(y, logicalHeight);
    v.r = (float)rgba[0] / 255.0f;
    v.g = (float)rgba[1] / 255.0f;
    v.b = (float)rgba[2] / 255.0f;
    v.a = (float)rgba[3] / 255.0f;
    return v;
}

static void OrenAVMMetalAppendRect(NSMutableData* vertices,
                                   float x,
                                   float y,
                                   float w,
                                   float h,
                                   float logicalWidth,
                                   float logicalHeight,
                                   const uint8_t* rgba) {
    OrenAVMMetalVertex out[6];
    out[0] = OrenAVMMetalMakeVertex(x, y, logicalWidth, logicalHeight, rgba);
    out[1] = OrenAVMMetalMakeVertex(x + w, y, logicalWidth, logicalHeight, rgba);
    out[2] = OrenAVMMetalMakeVertex(x, y + h, logicalWidth, logicalHeight, rgba);
    out[3] = OrenAVMMetalMakeVertex(x + w, y, logicalWidth, logicalHeight, rgba);
    out[4] = OrenAVMMetalMakeVertex(x + w, y + h, logicalWidth, logicalHeight, rgba);
    out[5] = OrenAVMMetalMakeVertex(x, y + h, logicalWidth, logicalHeight, rgba);
    [vertices appendBytes:out length:sizeof(out)];
}

static void OrenAVMMetalAppendLine(NSMutableData* vertices,
                                   float x1,
                                   float y1,
                                   float x2,
                                   float y2,
                                   float width,
                                   float logicalWidth,
                                   float logicalHeight,
                                   const uint8_t* rgba) {
    float dx = x2 - x1;
    float dy = y2 - y1;
    float len = sqrtf(dx * dx + dy * dy);
    if (len <= 0.0001f) {
        float side = width <= 0.0f ? 1.0f : width;
        OrenAVMMetalAppendRect(vertices, x1, y1, side, side, logicalWidth, logicalHeight, rgba);
        return;
    }
    float halfWidth = (width <= 0.0f ? 1.0f : width) * 0.5f;
    float nx = -dy / len * halfWidth;
    float ny = dx / len * halfWidth;
    OrenAVMMetalVertex out[6];
    out[0] = OrenAVMMetalMakeVertex(x1 + nx, y1 + ny, logicalWidth, logicalHeight, rgba);
    out[1] = OrenAVMMetalMakeVertex(x2 + nx, y2 + ny, logicalWidth, logicalHeight, rgba);
    out[2] = OrenAVMMetalMakeVertex(x1 - nx, y1 - ny, logicalWidth, logicalHeight, rgba);
    out[3] = OrenAVMMetalMakeVertex(x2 + nx, y2 + ny, logicalWidth, logicalHeight, rgba);
    out[4] = OrenAVMMetalMakeVertex(x2 - nx, y2 - ny, logicalWidth, logicalHeight, rgba);
    out[5] = OrenAVMMetalMakeVertex(x1 - nx, y1 - ny, logicalWidth, logicalHeight, rgba);
    [vertices appendBytes:out length:sizeof(out)];
}

static void OrenAVMMetalAppendStrokeRect(NSMutableData* vertices,
                                         float x,
                                         float y,
                                         float w,
                                         float h,
                                         float width,
                                         float logicalWidth,
                                         float logicalHeight,
                                         const uint8_t* rgba) {
    float lw = width <= 0.0f ? 1.0f : width;
    OrenAVMMetalAppendRect(vertices, x, y, w, lw, logicalWidth, logicalHeight, rgba);
    OrenAVMMetalAppendRect(vertices, x, y + h - lw, w, lw, logicalWidth, logicalHeight, rgba);
    OrenAVMMetalAppendRect(vertices, x, y, lw, h, logicalWidth, logicalHeight, rgba);
    OrenAVMMetalAppendRect(vertices, x + w - lw, y, lw, h, logicalWidth, logicalHeight, rgba);
}

static void OrenAVMMetalAppendTriangle(NSMutableData* vertices,
                                       float x1,
                                       float y1,
                                       float x2,
                                       float y2,
                                       float x3,
                                       float y3,
                                       float logicalWidth,
                                       float logicalHeight,
                                       const uint8_t* rgba) {
    OrenAVMMetalVertex out[3];
    out[0] = OrenAVMMetalMakeVertex(x1, y1, logicalWidth, logicalHeight, rgba);
    out[1] = OrenAVMMetalMakeVertex(x2, y2, logicalWidth, logicalHeight, rgba);
    out[2] = OrenAVMMetalMakeVertex(x3, y3, logicalWidth, logicalHeight, rgba);
    [vertices appendBytes:out length:sizeof(out)];
}

static void OrenAVMMetalAppendCircle(NSMutableData* vertices,
                                     float cx,
                                     float cy,
                                     float radius,
                                     BOOL filled,
                                     float logicalWidth,
                                     float logicalHeight,
                                     const uint8_t* rgba) {
    if (radius <= 0.0f) return;
    const int segments = 32;
    const float pi = acosf(-1.0f);
    if (filled) {
        for (int i = 0; i < segments; i++) {
            float a0 = ((float)i / (float)segments) * 2.0f * pi;
            float a1 = ((float)(i + 1) / (float)segments) * 2.0f * pi;
            OrenAVMMetalVertex out[3];
            out[0] = OrenAVMMetalMakeVertex(cx, cy, logicalWidth, logicalHeight, rgba);
            out[1] = OrenAVMMetalMakeVertex(cx + cosf(a0) * radius,
                                            cy + sinf(a0) * radius,
                                            logicalWidth,
                                            logicalHeight,
                                            rgba);
            out[2] = OrenAVMMetalMakeVertex(cx + cosf(a1) * radius,
                                            cy + sinf(a1) * radius,
                                            logicalWidth,
                                            logicalHeight,
                                            rgba);
            [vertices appendBytes:out length:sizeof(out)];
        }
        return;
    }
    for (int i = 0; i < segments; i++) {
        float a0 = ((float)i / (float)segments) * 2.0f * pi;
        float a1 = ((float)(i + 1) / (float)segments) * 2.0f * pi;
        OrenAVMMetalAppendLine(vertices,
                               cx + cosf(a0) * radius,
                               cy + sinf(a0) * radius,
                               cx + cosf(a1) * radius,
                               cy + sinf(a1) * radius,
                               1.0f,
                               logicalWidth,
                               logicalHeight,
                               rgba);
    }
}

static void OrenAVMMetalAppendEllipse(NSMutableData* vertices,
                                      float x,
                                      float y,
                                      float w,
                                      float h,
                                      float width,
                                      BOOL filled,
                                      float logicalWidth,
                                      float logicalHeight,
                                      const uint8_t* rgba) {
    if (w <= 0.0f || h <= 0.0f) return;
    const int segments = 32;
    const float pi = acosf(-1.0f);
    float cx = x + (w * 0.5f);
    float cy = y + (h * 0.5f);
    float rx = w * 0.5f;
    float ry = h * 0.5f;
    if (filled) {
        for (int i = 0; i < segments; i++) {
            float a0 = ((float)i / (float)segments) * 2.0f * pi;
            float a1 = ((float)(i + 1) / (float)segments) * 2.0f * pi;
            OrenAVMMetalVertex out[3];
            out[0] = OrenAVMMetalMakeVertex(cx, cy, logicalWidth, logicalHeight, rgba);
            out[1] = OrenAVMMetalMakeVertex(cx + cosf(a0) * rx,
                                            cy + sinf(a0) * ry,
                                            logicalWidth,
                                            logicalHeight,
                                            rgba);
            out[2] = OrenAVMMetalMakeVertex(cx + cosf(a1) * rx,
                                            cy + sinf(a1) * ry,
                                            logicalWidth,
                                            logicalHeight,
                                            rgba);
            [vertices appendBytes:out length:sizeof(out)];
        }
        return;
    }
    float lw = width <= 0.0f ? 1.0f : width;
    for (int i = 0; i < segments; i++) {
        float a0 = ((float)i / (float)segments) * 2.0f * pi;
        float a1 = ((float)(i + 1) / (float)segments) * 2.0f * pi;
        OrenAVMMetalAppendLine(vertices,
                               cx + cosf(a0) * rx,
                               cy + sinf(a0) * ry,
                               cx + cosf(a1) * rx,
                               cy + sinf(a1) * ry,
                               lw,
                               logicalWidth,
                               logicalHeight,
                               rgba);
    }
}

static NSData* OrenAVMMetalTextureQuad(float x,
                                       float y,
                                       float w,
                                       float h,
                                       float logicalWidth,
                                       float logicalHeight,
                                       float u0,
                                       float v0,
                                       float u1,
                                       float v1) {
    OrenAVMMetalTextVertex out[6];
    out[0] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x, logicalWidth),
                                      OrenAVMMetalClipY(y, logicalHeight),
                                      u0,
                                      v0};
    out[1] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x + w, logicalWidth),
                                      OrenAVMMetalClipY(y, logicalHeight),
                                      u1,
                                      v0};
    out[2] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x, logicalWidth),
                                      OrenAVMMetalClipY(y + h, logicalHeight),
                                      u0,
                                      v1};
    out[3] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x + w, logicalWidth),
                                      OrenAVMMetalClipY(y, logicalHeight),
                                      u1,
                                      v0};
    out[4] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x + w, logicalWidth),
                                      OrenAVMMetalClipY(y + h, logicalHeight),
                                      u1,
                                      v1};
    out[5] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x, logicalWidth),
                                      OrenAVMMetalClipY(y + h, logicalHeight),
                                      u0,
                                      v1};
    return [NSData dataWithBytes:out length:sizeof(out)];
}

static NSData* OrenAVMMetalTextQuad(float x,
                                    float y,
                                    float w,
                                    float h,
                                    float logicalWidth,
                                    float logicalHeight) {
    return OrenAVMMetalTextureQuad(x, y, w, h, logicalWidth, logicalHeight, 0.0f, 0.0f, 1.0f, 1.0f);
}

@interface OrenAVMMetalView () <MTKViewDelegate>
@property(nonatomic, strong, nullable) id<MTLCommandQueue> orenCommandQueue;
@property(nonatomic, strong, nullable) id<MTLRenderPipelineState> orenPipelineState;
@property(nonatomic, strong, nullable) id<MTLRenderPipelineState> orenTextPipelineState;
@property(nonatomic, strong) NSMutableDictionary<NSString*, OrenAVMMetalTextCacheEntry*>* orenTextCache;
@property(nonatomic, strong) NSMutableArray<NSString*>* orenTextCacheOrder;
@property(nonatomic) NSUInteger orenTextCachePixels;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, OrenAVMMetalTextResource*>* orenTextResources;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, id<MTLTexture>>* orenImageTextures;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, NSNumber*>* orenImagePixels;
@property(nonatomic, readwrite) NSUInteger retainedImagePixelCount;
@property(nonatomic) uint32_t orenFrameTickSequence;
@property(nonatomic) uint64_t orenLastFrameTickNs;
@property(nonatomic, readwrite) uint64_t renderedFrameCount;
@property(nonatomic, readwrite) uint64_t lastFrameCPUNs;
@property(nonatomic, readwrite) uint64_t lastFrameTargetBudgetNs;
@property(nonatomic, readwrite) uint32_t lastFrameVertexCount;
@property(nonatomic, readwrite) uint32_t lastFrameTextRunCount;
@property(nonatomic, strong) NSMapTable<UITouch*, NSNumber*>* orenTouchIDs;
@property(nonatomic) uint32_t orenNextTouchID;
@end

@implementation OrenAVMMetalView

- (instancetype)initWithRuntime:(OrenAVMRuntime*)runtime {
    self = [super initWithFrame:CGRectZero device:MTLCreateSystemDefaultDevice()];
    if (!self) return nil;
    _runtime = runtime;
    [self orenConfigureMetalView];
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame device:(id<MTLDevice>)device {
    self = [super initWithFrame:frame device:device ?: MTLCreateSystemDefaultDevice()];
    if (!self) return nil;
    [self orenConfigureMetalView];
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    self = [super initWithCoder:coder];
    if (!self) return nil;
    if (!self.device) self.device = MTLCreateSystemDefaultDevice();
    [self orenConfigureMetalView];
    return self;
}

- (void)orenConfigureMetalView {
    self.multipleTouchEnabled = YES;
    self.framebufferOnly = YES;
    self.paused = NO;
    self.enableSetNeedsDisplay = NO;
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    if (!self.orenTextCache) self.orenTextCache = [NSMutableDictionary dictionary];
    if (!self.orenTextCacheOrder) self.orenTextCacheOrder = [NSMutableArray array];
    if (!self.orenTextResources) self.orenTextResources = [NSMutableDictionary dictionary];
    if (!self.orenImageTextures) self.orenImageTextures = [NSMutableDictionary dictionary];
    if (!self.orenImagePixels) self.orenImagePixels = [NSMutableDictionary dictionary];
    if (!self.orenTouchIDs) self.orenTouchIDs = [NSMapTable strongToStrongObjectsMapTable];
    if (self.orenNextTouchID == 0) self.orenNextTouchID = 1u;
    if (self.targetHzMilli == 0) self.targetHzMilli = 60000u;
    if (self.frameBudgetWarningPermille == 0) self.frameBudgetWarningPermille = 1000u;
    if (self.retainedImagePixelLimit == 0) self.retainedImagePixelLimit = OrenAVMMetalDefaultRetainedImagePixelLimit;
    if (self.retainedImageCountLimit == 0) self.retainedImageCountLimit = OrenAVMMetalDefaultRetainedImageCountLimit;
    self.lastFrameTargetBudgetNs = OrenAVMMetalTargetBudgetNs(self.targetHzMilli);
    [self orenApplyFrameRate];
    if (self.device) {
        self.orenCommandQueue = [self.device newCommandQueue];
        [self orenBuildPipeline];
    }
    self.delegate = self;
}

- (void)setTargetHzMilli:(uint32_t)targetHzMilli {
    _targetHzMilli = targetHzMilli;
    self.lastFrameTargetBudgetNs = OrenAVMMetalTargetBudgetNs(targetHzMilli);
    [self orenApplyFrameRate];
}

- (void)orenApplyFrameRate {
    uint32_t hzMilli = self.targetHzMilli == 0 ? 60000u : self.targetHzMilli;
    NSInteger fps = (NSInteger)((hzMilli + 999u) / 1000u);
    if (fps <= 0) fps = 60;
    self.preferredFramesPerSecond = fps;
}

- (void)orenBuildPipeline {
    if (!self.device) return;
    NSString* source =
        @"#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "struct V { float2 pos; float4 color; };\n"
        "struct O { float4 position [[position]]; float4 color; };\n"
        "struct TV { float2 pos; float2 uv; };\n"
        "struct TO { float4 position [[position]]; float2 uv; };\n"
        "vertex O oren_vertex(uint vid [[vertex_id]], constant V* verts [[buffer(0)]]) {\n"
        "  O o; o.position = float4(verts[vid].pos, 0.0, 1.0); o.color = verts[vid].color; return o;\n"
        "}\n"
        "fragment float4 oren_fragment(O in [[stage_in]]) { return in.color; }\n"
        "vertex TO oren_text_vertex(uint vid [[vertex_id]], constant TV* verts [[buffer(0)]]) {\n"
        "  TO o; o.position = float4(verts[vid].pos, 0.0, 1.0); o.uv = verts[vid].uv; return o;\n"
        "}\n"
        "fragment float4 oren_text_fragment(TO in [[stage_in]], texture2d<float> tex [[texture(0)]]) {\n"
        "  constexpr sampler s(address::clamp_to_edge, filter::linear); return tex.sample(s, in.uv);\n"
        "}\n";
    NSError* error = nil;
    id<MTLLibrary> library = [self.device newLibraryWithSource:source options:nil error:&error];
    if (!library) return;
    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"oren_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"oren_fragment"];
    descriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    descriptor.colorAttachments[0].blendingEnabled = YES;
    descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    self.orenPipelineState = [self.device newRenderPipelineStateWithDescriptor:descriptor error:&error];

    MTLRenderPipelineDescriptor* textDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    textDescriptor.vertexFunction = [library newFunctionWithName:@"oren_text_vertex"];
    textDescriptor.fragmentFunction = [library newFunctionWithName:@"oren_text_fragment"];
    textDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;
    textDescriptor.colorAttachments[0].blendingEnabled = YES;
    textDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    textDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    textDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    textDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    self.orenTextPipelineState = [self.device newRenderPipelineStateWithDescriptor:textDescriptor error:&error];
}

- (BOOL)reloadFrameWithError:(NSError**)error {
    if (!self.runtime) {
        return OrenAVMMetalAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                       @"metal view has no AVM runtime");
    }
    NSData* frame = [self.runtime getGraphicsFrameDataWithError:error];
    if (!frame) return NO;
    self.frameData = frame;
    return YES;
}

- (void)clearTextTextureCache {
    [self.orenTextCache removeAllObjects];
    [self.orenTextCacheOrder removeAllObjects];
    self.orenTextCachePixels = 0;
}

- (void)clearImageTextureCache {
    [self.orenImageTextures removeAllObjects];
    [self.orenImagePixels removeAllObjects];
    self.retainedImagePixelCount = 0;
}

- (NSUInteger)retainedImageCount {
    return self.orenImageTextures.count;
}

- (void)resetFrameMetrics {
    self.renderedFrameCount = 0;
    self.lastFrameCPUNs = 0;
    self.lastFrameTargetBudgetNs = OrenAVMMetalTargetBudgetNs(self.targetHzMilli);
    self.lastFrameVertexCount = 0;
    self.lastFrameTextRunCount = 0;
}

- (uint32_t)lastFrameBudgetUsagePermille {
    if (self.lastFrameTargetBudgetNs == 0) return 0;
    long double usage = ((long double)self.lastFrameCPUNs * 1000.0L) / (long double)self.lastFrameTargetBudgetNs;
    if (usage <= 0.0L) return 0;
    if (usage > 4294967295.0L) return UINT32_MAX;
    return (uint32_t)usage;
}

- (BOOL)frameCPUNsExceedsBudget:(uint64_t)cpuNs {
    if (self.frameBudgetWarningPermille == 0 || self.lastFrameTargetBudgetNs == 0) return NO;
    long double lhs = (long double)cpuNs * 1000.0L;
    long double rhs = (long double)self.lastFrameTargetBudgetNs * (long double)self.frameBudgetWarningPermille;
    return lhs > rhs;
}

- (BOOL)lastFrameOverBudget {
    return [self frameCPUNsExceedsBudget:self.lastFrameCPUNs];
}

- (void)orenEmitFrameTick {
    if (!self.runtime) return;
    uint64_t nowNs = OrenAVMMetalNowNs();
    uint64_t deltaNs = self.orenLastFrameTickNs == 0 ? 0 : nowNs - self.orenLastFrameTickNs;
    self.orenLastFrameTickNs = nowNs;
    self.orenFrameTickSequence += 1u;
    (void)[self.runtime putGraphicsFrameTickEventWithSequence:self.orenFrameTickSequence
                                                        nowNs:nowNs
                                                      deltaNs:deltaNs
                                                targetHzMilli:self.targetHzMilli
                                                        flags:self.mediaFlags
                                                        error:nil];
}

- (BOOL)sendPointerEventWithKind:(uint8_t)kind point:(CGPoint)point pointerId:(uint32_t)pointerId error:(NSError**)error {
    if (!self.runtime) {
        return OrenAVMMetalAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                       @"metal view has no AVM runtime");
    }
    return [self.runtime putGraphicsPointerEventWithKind:kind
                                                       x:(int32_t)llround((double)point.x)
                                                       y:(int32_t)llround((double)point.y)
                                               pointerId:pointerId
                                                   error:error];
}

- (BOOL)sendPointerEventsWithKind:(uint8_t)kind points:(NSArray<NSValue*>*)points pointerIDs:(NSArray<NSNumber*>*)pointerIDs error:(NSError**)error {
    if (points.count != pointerIDs.count) {
        return OrenAVMMetalAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                       @"metal view pointer batch point/id count mismatch");
    }
    for (NSUInteger i = 0; i < points.count; i++) {
        if (![self sendPointerEventWithKind:kind
                                      point:points[i].CGPointValue
                                  pointerId:pointerIDs[i].unsignedIntValue
                                      error:error]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)publishScreenStateWithError:(NSError**)error {
    if (!self.runtime) {
        return OrenAVMMetalAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                       @"metal view has no AVM runtime");
    }
    CGSize logical = self.bounds.size;
    CGSize drawable = self.drawableSize;
    CGFloat scale = self.window.screen.scale;
    if (scale <= 0.0) scale = UIScreen.mainScreen.scale;
    if (drawable.width <= 0.0 || drawable.height <= 0.0) {
        drawable = CGSizeMake(logical.width * scale, logical.height * scale);
    }
    uint32_t hz = self.targetHzMilli;
    if (hz == 0) hz = (uint32_t)UIScreen.mainScreen.maximumFramesPerSecond * 1000u;
    return [self.runtime setGraphicsScreenWithID:0
                                           width:(uint32_t)llround((double)logical.width)
                                          height:(uint32_t)llround((double)logical.height)
                                      scaleMilli:(uint32_t)llround((double)scale * 1000.0)
                                   drawableWidth:(uint32_t)llround((double)drawable.width)
                                  drawableHeight:(uint32_t)llround((double)drawable.height)
                                   targetHzMilli:hz
                                           flags:self.mediaFlags
                                           error:error];
}

- (BOOL)sendMediaEventWithError:(NSError**)error {
    if (![self publishScreenStateWithError:error]) return NO;
    CGSize logical = self.bounds.size;
    CGSize drawable = self.drawableSize;
    CGFloat scale = self.window.screen.scale;
    if (scale <= 0.0) scale = UIScreen.mainScreen.scale;
    if (drawable.width <= 0.0 || drawable.height <= 0.0) {
        drawable = CGSizeMake(logical.width * scale, logical.height * scale);
    }
    uint32_t hz = self.targetHzMilli;
    if (hz == 0) hz = (uint32_t)UIScreen.mainScreen.maximumFramesPerSecond * 1000u;
    return [self.runtime putGraphicsMediaEventWithWidth:(uint32_t)llround((double)logical.width)
                                                 height:(uint32_t)llround((double)logical.height)
                                             scaleMilli:(uint32_t)llround((double)scale * 1000.0)
                                          drawableWidth:(uint32_t)llround((double)drawable.width)
                                         drawableHeight:(uint32_t)llround((double)drawable.height)
                                          targetHzMilli:hz
                                                  flags:self.mediaFlags
                                                  error:error];
}

- (NSString*)orenTextCacheKeyWithText:(NSString*)text rgba:(const uint8_t*)rgba scaleMilli:(uint32_t)scaleMilli {
    return [NSString stringWithFormat:@"%u:%u:%u:%u:%u:%@",
            scaleMilli,
            (unsigned)rgba[0],
            (unsigned)rgba[1],
            (unsigned)rgba[2],
            (unsigned)rgba[3],
            text ?: @""];
}

- (void)orenTouchTextCacheKey:(NSString*)key {
    if (!key) return;
    [self.orenTextCacheOrder removeObject:key];
    [self.orenTextCacheOrder addObject:key];
}

- (void)orenTrimTextCache {
    while ((self.orenTextCachePixels > OrenAVMMetalTextCachePixelLimit ||
            self.orenTextCacheOrder.count > OrenAVMMetalTextCacheEntryLimit) &&
           self.orenTextCacheOrder.count > 0) {
        NSString* key = self.orenTextCacheOrder.firstObject;
        [self.orenTextCacheOrder removeObjectAtIndex:0];
        OrenAVMMetalTextCacheEntry* entry = self.orenTextCache[key];
        if (entry) {
            self.orenTextCachePixels = self.orenTextCachePixels > entry.pixelCount
                ? self.orenTextCachePixels - entry.pixelCount
                : 0;
            [self.orenTextCache removeObjectForKey:key];
        }
    }
}

- (OrenAVMMetalTextCacheEntry*)orenTextCacheEntryWithText:(NSString*)text rgba:(const uint8_t*)rgba {
    if (!text || text.length == 0 || !self.device) return nil;
    UIFont* font = [UIFont systemFontOfSize:14.0];
    UIColor* color = [UIColor colorWithRed:(CGFloat)rgba[0] / 255.0
                                     green:(CGFloat)rgba[1] / 255.0
                                      blue:(CGFloat)rgba[2] / 255.0
                                     alpha:(CGFloat)rgba[3] / 255.0];
    NSDictionary<NSAttributedStringKey, id>* attrs = @{
        NSForegroundColorAttributeName: color,
        NSFontAttributeName: font
    };
    CGSize textSize = [text sizeWithAttributes:attrs];
    if (textSize.width <= 0.0 || textSize.height <= 0.0) return nil;
    CGFloat scale = self.window.screen.scale;
    if (scale <= 0.0) scale = UIScreen.mainScreen.scale;
    if (scale <= 0.0) scale = 1.0;
    uint32_t scaleMilli = (uint32_t)llround((double)scale * 1000.0);
    NSString* cacheKey = [self orenTextCacheKeyWithText:text rgba:rgba scaleMilli:scaleMilli];
    OrenAVMMetalTextCacheEntry* cached = self.orenTextCache[cacheKey];
    if (cached) {
        [self orenTouchTextCacheKey:cacheKey];
        return cached;
    }

    NSUInteger pixelWidth = (NSUInteger)ceil(textSize.width * scale);
    NSUInteger pixelHeight = (NSUInteger)ceil(textSize.height * scale);
    if (pixelWidth == 0 || pixelHeight == 0 || pixelWidth > 4096u || pixelHeight > 4096u) return nil;

    NSMutableData* pixels = [NSMutableData dataWithLength:pixelWidth * pixelHeight * 4u];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels.mutableBytes,
                                             pixelWidth,
                                             pixelHeight,
                                             8,
                                             pixelWidth * 4u,
                                             colorSpace,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!ctx) return nil;
    CGContextClearRect(ctx, CGRectMake(0.0, 0.0, (CGFloat)pixelWidth, (CGFloat)pixelHeight));
    CGContextScaleCTM(ctx, scale, scale);
    UIGraphicsPushContext(ctx);
    [text drawAtPoint:CGPointZero withAttributes:attrs];
    UIGraphicsPopContext();
    CGContextRelease(ctx);

    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                         width:pixelWidth
                                                                                        height:pixelHeight
                                                                                     mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [self.device newTextureWithDescriptor:descriptor];
    if (!texture) return nil;
    [texture replaceRegion:MTLRegionMake2D(0, 0, pixelWidth, pixelHeight)
               mipmapLevel:0
                 withBytes:pixels.bytes
               bytesPerRow:pixelWidth * 4u];

    OrenAVMMetalTextCacheEntry* entry = [[OrenAVMMetalTextCacheEntry alloc] init];
    entry.texture = texture;
    entry.logicalSize = textSize;
    entry.pixelCount = pixelWidth * pixelHeight;
    self.orenTextCache[cacheKey] = entry;
    self.orenTextCachePixels += entry.pixelCount;
    [self orenTouchTextCacheKey:cacheKey];
    [self orenTrimTextCache];
    return entry;
}

- (OrenAVMMetalTextRun*)orenTextRunWithText:(NSString*)text
                                          x:(float)x
                                          y:(float)y
                                        rgba:(const uint8_t*)rgba
                                logicalWidth:(float)logicalWidth
                               logicalHeight:(float)logicalHeight {
    OrenAVMMetalTextCacheEntry* entry = [self orenTextCacheEntryWithText:text rgba:rgba];
    if (!entry) return nil;
    OrenAVMMetalTextRun* run = [[OrenAVMMetalTextRun alloc] init];
    run.texture = entry.texture;
    run.vertices = OrenAVMMetalTextQuad(x,
                                        y,
                                        (float)entry.logicalSize.width,
                                        (float)entry.logicalSize.height,
                                        logicalWidth,
                                        logicalHeight);
    return run;
}

- (void)orenPutImageTextureWithID:(uint32_t)imageID
                            width:(uint32_t)width
                           height:(uint32_t)height
                             rgba:(const uint8_t*)rgba
                        byteCount:(uint32_t)byteCount {
    if (!self.device || imageID == 0 || width == 0 || height == 0 || !rgba) return;
    uint64_t expected = (uint64_t)width * (uint64_t)height * 4ull;
    if (expected != (uint64_t)byteCount) return;
    NSUInteger pixels = (NSUInteger)width * (NSUInteger)height;
    NSNumber* key = @(imageID);
    NSNumber* oldPixels = self.orenImagePixels[key];
    NSUInteger old = oldPixels ? oldPixels.unsignedIntegerValue : 0;
    NSUInteger countAfter = self.orenImageTextures[key] ? self.orenImageTextures.count : self.orenImageTextures.count + 1u;
    NSUInteger pixelAfter = self.retainedImagePixelCount >= old ? self.retainedImagePixelCount - old + pixels : pixels;
    if (self.retainedImageCountLimit == 0 || countAfter > self.retainedImageCountLimit) return;
    if (self.retainedImagePixelLimit == 0 || pixels > self.retainedImagePixelLimit || pixelAfter > self.retainedImagePixelLimit) return;
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                          width:(NSUInteger)width
                                                                                         height:(NSUInteger)height
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [self.device newTextureWithDescriptor:descriptor];
    if (!texture) return;
    [texture replaceRegion:MTLRegionMake2D(0, 0, (NSUInteger)width, (NSUInteger)height)
               mipmapLevel:0
                 withBytes:rgba
               bytesPerRow:(NSUInteger)width * 4u];
    self.orenImageTextures[key] = texture;
    self.orenImagePixels[key] = @(pixels);
    self.retainedImagePixelCount = pixelAfter;
}

- (OrenAVMMetalImageRun*)orenImageRunWithID:(uint32_t)imageID
                                         sx:(uint32_t)sx
                                         sy:(uint32_t)sy
                                         sw:(uint32_t)sw
                                         sh:(uint32_t)sh
                                          x:(float)x
                                          y:(float)y
                                          w:(float)w
                                          h:(float)h
                               logicalWidth:(float)logicalWidth
                              logicalHeight:(float)logicalHeight {
    id<MTLTexture> texture = self.orenImageTextures[@(imageID)];
    if (!texture || w <= 0.0f || h <= 0.0f || sw == 0 || sh == 0) return nil;
    if ((NSUInteger)sx + (NSUInteger)sw > texture.width || (NSUInteger)sy + (NSUInteger)sh > texture.height) return nil;
    float u0 = (float)sx / (float)texture.width;
    float v0 = (float)sy / (float)texture.height;
    float u1 = (float)(sx + sw) / (float)texture.width;
    float v1 = (float)(sy + sh) / (float)texture.height;
    OrenAVMMetalImageRun* run = [[OrenAVMMetalImageRun alloc] init];
    run.texture = texture;
    run.vertices = OrenAVMMetalTextureQuad(x, y, w, h, logicalWidth, logicalHeight, u0, v0, u1, v1);
    return run;
}

- (NSArray<OrenAVMMetalVertexRun*>*)orenVertexRunsForFrame:(NSData*)frame
                                                 clearColor:(MTLClearColor*)clearColor
                                                   textRuns:(NSMutableArray<OrenAVMMetalTextRun*>*)textRuns
                                                  imageRuns:(NSMutableArray<OrenAVMMetalImageRun*>*)imageRuns {
    NSMutableArray<OrenAVMMetalVertexRun*>* vertexRuns = [NSMutableArray array];
    NSMutableData* vertices = [NSMutableData data];
    if (frame.length < 40) return vertexRuns;
    const uint8_t* data = (const uint8_t*)frame.bytes;
    if (memcmp(data, "OGF0", 4) != 0 || data[4] != 1) return vertexRuns;
    uint16_t headerLen = OrenAVMMetalReadU16LE(data + 6);
    if (headerLen < 40 || headerLen > frame.length) return vertexRuns;
    uint32_t logicalW = OrenAVMMetalReadU32LE(data + 8);
    uint32_t logicalH = OrenAVMMetalReadU32LE(data + 12);
    uint32_t opCount = OrenAVMMetalReadU32LE(data + 20);
    uint32_t drawableW = OrenAVMMetalReadU32LE(data + 28);
    uint32_t drawableH = OrenAVMMetalReadU32LE(data + 32);
    if (logicalW == 0 || logicalH == 0 || drawableW == 0 || drawableH == 0) return vertexRuns;

    size_t off = headerLen;
    OrenAVMMetalScissorState clip;
    clip.enabled = NO;
    clip.rect = (MTLScissorRect){0, 0, 0, 0};
    OrenAVMMetalScissorState clipStack[64];
    uint32_t clipDepth = 0;
    float tx = 0.0f;
    float ty = 0.0f;
    float txStack[64];
    float tyStack[64];
    uint32_t transformDepth = 0;
    for (uint32_t i = 0; i < opCount && off + 4 <= frame.length; i++) {
        uint8_t opcode = data[off];
        uint16_t payloadLen = OrenAVMMetalReadU16LE(data + off + 2);
        off += 4;
        if (off + (size_t)payloadLen > frame.length) break;
        const uint8_t* payload = data + off;
        if (opcode == 1 && payloadLen == 20) {
            uint32_t x = OrenAVMMetalReadU32LE(payload);
            uint32_t y = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t w = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t h = OrenAVMMetalReadU32LE(payload + 12);
            const uint8_t* rgba = payload + 16;
            if (x == 0 && y == 0 && w >= logicalW && h >= logicalH && clearColor) {
                *clearColor = MTLClearColorMake((double)rgba[0] / 255.0,
                                                (double)rgba[1] / 255.0,
                                                (double)rgba[2] / 255.0,
                                                (double)rgba[3] / 255.0);
            }
            OrenAVMMetalAppendRect(vertices, (float)x + tx, (float)y + ty, (float)w, (float)h,
                                   (float)logicalW, (float)logicalH, rgba);
        } else if (opcode == 16 && payloadLen == 16) {
            OrenAVMMetalFlushVertexRun(vertexRuns, vertices, clip);
            if (clipDepth < 64) {
                clipStack[clipDepth++] = clip;
                int32_t cx = (int32_t)OrenAVMMetalReadU32LE(payload);
                int32_t cy = (int32_t)OrenAVMMetalReadU32LE(payload + 4);
                MTLScissorRect next = OrenAVMMetalClipRectToScissor((int64_t)lrintf((float)cx + tx),
                                                                    (int64_t)lrintf((float)cy + ty),
                                                                    OrenAVMMetalReadU32LE(payload + 8),
                                                                    OrenAVMMetalReadU32LE(payload + 12),
                                                                    logicalW,
                                                                    logicalH,
                                                                    drawableW,
                                                                    drawableH);
                clip.rect = clip.enabled ? OrenAVMMetalIntersectScissor(clip.rect, next) : next;
                clip.enabled = YES;
            }
        } else if (opcode == 17 && payloadLen == 0) {
            OrenAVMMetalFlushVertexRun(vertexRuns, vertices, clip);
            if (clipDepth > 0) clip = clipStack[--clipDepth];
        } else if (opcode == 18 && payloadLen == 8) {
            OrenAVMMetalFlushVertexRun(vertexRuns, vertices, clip);
            if (transformDepth < 64) {
                txStack[transformDepth] = tx;
                tyStack[transformDepth] = ty;
                transformDepth++;
                tx += (float)(int32_t)OrenAVMMetalReadU32LE(payload);
                ty += (float)(int32_t)OrenAVMMetalReadU32LE(payload + 4);
            }
        } else if (opcode == 19 && payloadLen == 0) {
            OrenAVMMetalFlushVertexRun(vertexRuns, vertices, clip);
            if (transformDepth > 0) {
                transformDepth--;
                tx = txStack[transformDepth];
                ty = tyStack[transformDepth];
            }
        } else if (opcode == 3 && payloadLen == 24) {
            uint32_t x1 = OrenAVMMetalReadU32LE(payload);
            uint32_t y1 = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t x2 = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t y2 = OrenAVMMetalReadU32LE(payload + 12);
            uint32_t width = OrenAVMMetalReadU32LE(payload + 16);
            OrenAVMMetalAppendLine(vertices, (float)x1 + tx, (float)y1 + ty, (float)x2 + tx, (float)y2 + ty,
                                   (float)(width == 0 ? 1u : width),
                                   (float)logicalW, (float)logicalH, payload + 20);
        } else if (opcode == 6 && payloadLen == 24) {
            uint32_t x = OrenAVMMetalReadU32LE(payload);
            uint32_t y = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t w = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t h = OrenAVMMetalReadU32LE(payload + 12);
            uint32_t width = OrenAVMMetalReadU32LE(payload + 16);
            OrenAVMMetalAppendStrokeRect(vertices,
                                         (float)x + tx,
                                         (float)y + ty,
                                         (float)w,
                                         (float)h,
                                         (float)(width == 0 ? 1u : width),
                                         (float)logicalW,
                                         (float)logicalH,
                                         payload + 20);
        } else if (opcode == 4 && payloadLen == 20) {
            uint32_t cx = OrenAVMMetalReadU32LE(payload);
            uint32_t cy = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t radius = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t flags = OrenAVMMetalReadU32LE(payload + 12);
            OrenAVMMetalAppendCircle(vertices,
                                     (float)cx + tx,
                                     (float)cy + ty,
                                     (float)radius,
                                     (flags & 1u) != 0,
                                     (float)logicalW,
                                     (float)logicalH,
                                     payload + 16);
        } else if (opcode == 7 && payloadLen == 28) {
            uint32_t x = OrenAVMMetalReadU32LE(payload);
            uint32_t y = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t w = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t h = OrenAVMMetalReadU32LE(payload + 12);
            uint32_t width = OrenAVMMetalReadU32LE(payload + 16);
            uint32_t flags = OrenAVMMetalReadU32LE(payload + 20);
            OrenAVMMetalAppendEllipse(vertices,
                                      (float)x + tx,
                                      (float)y + ty,
                                      (float)w,
                                      (float)h,
                                      (float)(width == 0 ? 1u : width),
                                      (flags & 1u) != 0,
                                      (float)logicalW,
                                      (float)logicalH,
                                      payload + 24);
        } else if (opcode == 8 && payloadLen >= 28 && ((payloadLen - 12) % 8) == 0) {
            uint32_t width = OrenAVMMetalReadU32LE(payload);
            uint32_t pointCount = OrenAVMMetalReadU32LE(payload + 4);
            const uint8_t* rgba = payload + 8;
            const uint8_t* points = payload + 12;
            if (pointCount == ((uint32_t)payloadLen - 12u) / 8u && pointCount >= 2) {
                uint32_t lastX = OrenAVMMetalReadU32LE(points);
                uint32_t lastY = OrenAVMMetalReadU32LE(points + 4);
                for (uint32_t pi = 1; pi < pointCount; pi++) {
                    const uint8_t* point = points + ((size_t)pi * 8u);
                    uint32_t x = OrenAVMMetalReadU32LE(point);
                    uint32_t y = OrenAVMMetalReadU32LE(point + 4);
                    OrenAVMMetalAppendLine(vertices,
                                           (float)lastX + tx,
                                           (float)lastY + ty,
                                           (float)x + tx,
                                           (float)y + ty,
                                           (float)(width == 0 ? 1u : width),
                                           (float)logicalW,
                                           (float)logicalH,
                                           rgba);
                    lastX = x;
                    lastY = y;
                }
            }
        } else if (opcode == 5 && payloadLen == 28) {
            uint32_t x1 = OrenAVMMetalReadU32LE(payload);
            uint32_t y1 = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t x2 = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t y2 = OrenAVMMetalReadU32LE(payload + 12);
            uint32_t x3 = OrenAVMMetalReadU32LE(payload + 16);
            uint32_t y3 = OrenAVMMetalReadU32LE(payload + 20);
            OrenAVMMetalAppendTriangle(vertices,
                                       (float)x1 + tx,
                                       (float)y1 + ty,
                                       (float)x2 + tx,
                                       (float)y2 + ty,
                                       (float)x3 + tx,
                                       (float)y3 + ty,
                                       (float)logicalW,
                                       (float)logicalH,
                                       payload + 24);
        } else if (opcode == 2 && payloadLen >= 16) {
            uint32_t x = OrenAVMMetalReadU32LE(payload);
            uint32_t y = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t textLen = OrenAVMMetalReadU32LE(payload + 12);
            if (textLen == (uint32_t)payloadLen - 16u) {
                NSString* text = [[NSString alloc] initWithBytes:payload + 16
                                                          length:(NSUInteger)textLen
                                                        encoding:NSUTF8StringEncoding];
                OrenAVMMetalTextRun* run = [self orenTextRunWithText:text
                                                                    x:(float)x + tx
                                                                    y:(float)y + ty
                                                                  rgba:payload + 8
                                                          logicalWidth:(float)logicalW
	                                                         logicalHeight:(float)logicalH];
                if (run) {
                    run.hasScissor = clip.enabled;
                    run.scissor = clip.rect;
                    [textRuns addObject:run];
                }
            }
        } else if (opcode == 68 && payloadLen >= 12) {
            uint32_t textID = OrenAVMMetalReadU32LE(payload);
            uint32_t textLen = OrenAVMMetalReadU32LE(payload + 8);
            if (textLen == (uint32_t)payloadLen - 12u) {
                NSString* text = [[NSString alloc] initWithBytes:payload + 12
                                                          length:(NSUInteger)textLen
                                                        encoding:NSUTF8StringEncoding];
                if (text) {
                    OrenAVMMetalTextResource* resource = [[OrenAVMMetalTextResource alloc] init];
                    resource.text = text;
                    resource.rgba = [NSData dataWithBytes:payload + 4 length:4];
                    self.orenTextResources[@(textID)] = resource;
                }
            }
        } else if (opcode == 69 && payloadLen == 12) {
            uint32_t textID = OrenAVMMetalReadU32LE(payload);
            uint32_t x = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t y = OrenAVMMetalReadU32LE(payload + 8);
            OrenAVMMetalTextResource* resource = self.orenTextResources[@(textID)];
            if (resource.text && resource.rgba.length == 4) {
                OrenAVMMetalTextRun* run = [self orenTextRunWithText:resource.text
                                                                   x:(float)x + tx
                                                                   y:(float)y + ty
                                                                 rgba:resource.rgba.bytes
                                                         logicalWidth:(float)logicalW
                                                        logicalHeight:(float)logicalH];
                if (run) {
                    run.hasScissor = clip.enabled;
                    run.scissor = clip.rect;
                    [textRuns addObject:run];
                }
            }
        } else if (opcode == 70 && payloadLen == 4) {
            uint32_t textID = OrenAVMMetalReadU32LE(payload);
            [self.orenTextResources removeObjectForKey:@(textID)];
        } else if (opcode == 64 && payloadLen >= 16) {
            uint32_t imageID = OrenAVMMetalReadU32LE(payload);
            uint32_t iw = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t ih = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t imageLen = OrenAVMMetalReadU32LE(payload + 12);
            if (imageLen == (uint32_t)payloadLen - 16u) {
                [self orenPutImageTextureWithID:imageID
                                          width:iw
                                         height:ih
                                           rgba:payload + 16
                                      byteCount:imageLen];
            }
        } else if (opcode == 65 && payloadLen == 20) {
            uint32_t imageID = OrenAVMMetalReadU32LE(payload);
            uint32_t x = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t y = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t w = OrenAVMMetalReadU32LE(payload + 12);
            uint32_t h = OrenAVMMetalReadU32LE(payload + 16);
            OrenAVMMetalImageRun* run = [self orenImageRunWithID:imageID
                                                              sx:0
                                                              sy:0
                                                              sw:(uint32_t)self.orenImageTextures[@(imageID)].width
                                                              sh:(uint32_t)self.orenImageTextures[@(imageID)].height
                                                               x:(float)x + tx
                                                               y:(float)y + ty
                                                               w:(float)w
                                                               h:(float)h
	                                                    logicalWidth:(float)logicalW
	                                                   logicalHeight:(float)logicalH];
            if (run) {
                run.hasScissor = clip.enabled;
                run.scissor = clip.rect;
                [imageRuns addObject:run];
            }
        } else if (opcode == 66 && payloadLen == 4) {
            uint32_t imageID = OrenAVMMetalReadU32LE(payload);
            NSNumber* key = @(imageID);
            NSNumber* oldPixels = self.orenImagePixels[key];
            if (oldPixels) {
                NSUInteger pixels = oldPixels.unsignedIntegerValue;
                self.retainedImagePixelCount = self.retainedImagePixelCount > pixels ? self.retainedImagePixelCount - pixels : 0;
                [self.orenImagePixels removeObjectForKey:key];
            }
            [self.orenImageTextures removeObjectForKey:key];
        } else if (opcode == 67 && payloadLen == 36) {
            uint32_t imageID = OrenAVMMetalReadU32LE(payload);
            uint32_t sx = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t sy = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t sw = OrenAVMMetalReadU32LE(payload + 12);
            uint32_t sh = OrenAVMMetalReadU32LE(payload + 16);
            uint32_t x = OrenAVMMetalReadU32LE(payload + 20);
            uint32_t y = OrenAVMMetalReadU32LE(payload + 24);
            uint32_t w = OrenAVMMetalReadU32LE(payload + 28);
            uint32_t h = OrenAVMMetalReadU32LE(payload + 32);
            OrenAVMMetalImageRun* run = [self orenImageRunWithID:imageID
                                                              sx:sx
                                                              sy:sy
                                                              sw:sw
                                                              sh:sh
                                                               x:(float)x + tx
                                                               y:(float)y + ty
                                                               w:(float)w
                                                               h:(float)h
                                                    logicalWidth:(float)logicalW
	                                                    logicalHeight:(float)logicalH];
            if (run) {
                run.hasScissor = clip.enabled;
                run.scissor = clip.rect;
                [imageRuns addObject:run];
            }
        } else if (opcode == 71 && payloadLen >= 40 && ((payloadLen - 8) % 32) == 0) {
            uint32_t imageID = OrenAVMMetalReadU32LE(payload);
            uint32_t rectCount = OrenAVMMetalReadU32LE(payload + 4);
            if (rectCount == ((uint32_t)payloadLen - 8u) / 32u) {
                for (uint32_t ri = 0; ri < rectCount; ri++) {
                    const uint8_t* r = payload + 8 + ((size_t)ri * 32u);
                    OrenAVMMetalImageRun* run = [self orenImageRunWithID:imageID
                                                                      sx:OrenAVMMetalReadU32LE(r)
                                                                      sy:OrenAVMMetalReadU32LE(r + 4)
                                                                      sw:OrenAVMMetalReadU32LE(r + 8)
                                                                      sh:OrenAVMMetalReadU32LE(r + 12)
                                                                       x:(float)OrenAVMMetalReadU32LE(r + 16) + tx
                                                                       y:(float)OrenAVMMetalReadU32LE(r + 20) + ty
                                                                       w:(float)OrenAVMMetalReadU32LE(r + 24)
                                                                       h:(float)OrenAVMMetalReadU32LE(r + 28)
                                                            logicalWidth:(float)logicalW
                                                           logicalHeight:(float)logicalH];
                    if (run) {
                        run.hasScissor = clip.enabled;
                        run.scissor = clip.rect;
                        [imageRuns addObject:run];
                    }
                }
            }
        }
        off += payloadLen;
    }
    OrenAVMMetalFlushVertexRun(vertexRuns, vertices, clip);
    return vertexRuns;
}

- (void)drawInMTKView:(MTKView*)view {
    (void)view;
    if (!self.device || !self.orenCommandQueue) return;
    uint64_t cpuStartNs = OrenAVMMetalNowNs();
    (void)[self publishScreenStateWithError:nil];
    [self orenEmitFrameTick];
    (void)[self reloadFrameWithError:nil];

    id<CAMetalDrawable> drawable = self.currentDrawable;
    MTLRenderPassDescriptor* pass = self.currentRenderPassDescriptor;
    if (!drawable || !pass) return;

    MTLClearColor clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    NSMutableArray<OrenAVMMetalTextRun*>* textRuns = [NSMutableArray array];
    NSMutableArray<OrenAVMMetalImageRun*>* imageRuns = [NSMutableArray array];
    NSArray<OrenAVMMetalVertexRun*>* vertexRuns = [self orenVertexRunsForFrame:self.frameData
                                                                    clearColor:&clearColor
                                                                      textRuns:textRuns
                                                                     imageRuns:imageRuns];
    uint32_t vertexCount = 0;
    for (OrenAVMMetalVertexRun* run in vertexRuns) {
        vertexCount += (uint32_t)(run.vertices.length / sizeof(OrenAVMMetalVertex));
    }
    self.lastFrameVertexCount = vertexCount;
    self.lastFrameTextRunCount = (uint32_t)textRuns.count;
    pass.colorAttachments[0].clearColor = clearColor;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> commandBuffer = [self.orenCommandQueue commandBuffer];
    if (!commandBuffer) return;
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    if (!encoder) return;
    MTLScissorRect fullScissor = (MTLScissorRect){0, 0, (NSUInteger)drawable.texture.width, (NSUInteger)drawable.texture.height};
    if (encoder && self.orenPipelineState) {
        [encoder setRenderPipelineState:self.orenPipelineState];
        for (OrenAVMMetalVertexRun* run in vertexRuns) {
            if (run.vertices.length == 0) continue;
            MTLScissorRect scissor = run.hasScissor ? run.scissor : fullScissor;
            if (scissor.width == 0 || scissor.height == 0) continue;
            [encoder setScissorRect:scissor];
            [encoder setVertexBytes:run.vertices.bytes length:run.vertices.length atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                         vertexStart:0
                         vertexCount:run.vertices.length / sizeof(OrenAVMMetalVertex)];
        }
    }
    if (encoder && self.orenTextPipelineState) {
        [encoder setRenderPipelineState:self.orenTextPipelineState];
        for (OrenAVMMetalImageRun* run in imageRuns) {
            if (!run.texture || run.vertices.length == 0) continue;
            MTLScissorRect scissor = run.hasScissor ? run.scissor : fullScissor;
            if (scissor.width == 0 || scissor.height == 0) continue;
            [encoder setScissorRect:scissor];
            [encoder setVertexBytes:run.vertices.bytes length:run.vertices.length atIndex:0];
            [encoder setFragmentTexture:run.texture atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                         vertexStart:0
                         vertexCount:run.vertices.length / sizeof(OrenAVMMetalTextVertex)];
        }
        for (OrenAVMMetalTextRun* run in textRuns) {
            if (!run.texture || run.vertices.length == 0) continue;
            MTLScissorRect scissor = run.hasScissor ? run.scissor : fullScissor;
            if (scissor.width == 0 || scissor.height == 0) continue;
            [encoder setScissorRect:scissor];
            [encoder setVertexBytes:run.vertices.bytes length:run.vertices.length atIndex:0];
            [encoder setFragmentTexture:run.texture atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                         vertexStart:0
                         vertexCount:run.vertices.length / sizeof(OrenAVMMetalTextVertex)];
        }
    }
    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
    self.renderedFrameCount += 1u;
    self.lastFrameCPUNs = OrenAVMMetalNowNs() - cpuStartNs;
    self.lastFrameTargetBudgetNs = OrenAVMMetalTargetBudgetNs(self.targetHzMilli);
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    (void)size;
    (void)[self sendMediaEventWithError:nil];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    (void)[self publishScreenStateWithError:nil];
}

- (uint32_t)orenPointerIDForTouch:(UITouch*)touch {
    NSNumber* existing = [self.orenTouchIDs objectForKey:touch];
    if (existing) return existing.unsignedIntValue;
    uint32_t pointerID = self.orenNextTouchID == 0 ? 1u : self.orenNextTouchID;
    self.orenNextTouchID = pointerID + 1u;
    if (self.orenNextTouchID == 0) self.orenNextTouchID = 1u;
    [self.orenTouchIDs setObject:@(pointerID) forKey:touch];
    return pointerID;
}

- (void)orenSendTouches:(NSSet<UITouch*>*)touches kind:(uint8_t)kind releaseAfterSend:(BOOL)releaseAfterSend {
    for (UITouch* touch in touches) {
        CGPoint p = [touch locationInView:self];
        uint32_t pointerID = [self orenPointerIDForTouch:touch];
        NSError* error = nil;
        (void)[self sendPointerEventWithKind:kind
                                       point:p
                                   pointerId:pointerID
                                       error:&error];
        if (releaseAfterSend) [self.orenTouchIDs removeObjectForKey:touch];
    }
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self orenSendTouches:touches kind:1 releaseAfterSend:NO];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self orenSendTouches:touches kind:2 releaseAfterSend:NO];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self orenSendTouches:touches kind:3 releaseAfterSend:YES];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self orenSendTouches:touches kind:4 releaseAfterSend:YES];
}

@end

#endif
