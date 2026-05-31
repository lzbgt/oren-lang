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

@interface OrenAVMMetalTextRun : NSObject
@property(nonatomic, strong) id<MTLTexture> texture;
@property(nonatomic, strong) NSData* vertices;
@end

@implementation OrenAVMMetalTextRun
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

static NSData* OrenAVMMetalTextQuad(float x,
                                    float y,
                                    float w,
                                    float h,
                                    float logicalWidth,
                                    float logicalHeight) {
    OrenAVMMetalTextVertex out[6];
    out[0] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x, logicalWidth),
                                      OrenAVMMetalClipY(y, logicalHeight),
                                      0.0f,
                                      0.0f};
    out[1] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x + w, logicalWidth),
                                      OrenAVMMetalClipY(y, logicalHeight),
                                      1.0f,
                                      0.0f};
    out[2] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x, logicalWidth),
                                      OrenAVMMetalClipY(y + h, logicalHeight),
                                      0.0f,
                                      1.0f};
    out[3] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x + w, logicalWidth),
                                      OrenAVMMetalClipY(y, logicalHeight),
                                      1.0f,
                                      0.0f};
    out[4] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x + w, logicalWidth),
                                      OrenAVMMetalClipY(y + h, logicalHeight),
                                      1.0f,
                                      1.0f};
    out[5] = (OrenAVMMetalTextVertex){OrenAVMMetalClipX(x, logicalWidth),
                                      OrenAVMMetalClipY(y + h, logicalHeight),
                                      0.0f,
                                      1.0f};
    return [NSData dataWithBytes:out length:sizeof(out)];
}

@interface OrenAVMMetalView () <MTKViewDelegate>
@property(nonatomic, strong, nullable) id<MTLCommandQueue> orenCommandQueue;
@property(nonatomic, strong, nullable) id<MTLRenderPipelineState> orenPipelineState;
@property(nonatomic, strong, nullable) id<MTLRenderPipelineState> orenTextPipelineState;
@property(nonatomic, strong) NSMutableDictionary<NSString*, OrenAVMMetalTextCacheEntry*>* orenTextCache;
@property(nonatomic, strong) NSMutableArray<NSString*>* orenTextCacheOrder;
@property(nonatomic) NSUInteger orenTextCachePixels;
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
    if (!self.orenTouchIDs) self.orenTouchIDs = [NSMapTable strongToStrongObjectsMapTable];
    if (self.orenNextTouchID == 0) self.orenNextTouchID = 1u;
    if (self.targetHzMilli == 0) self.targetHzMilli = 60000u;
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

- (void)resetFrameMetrics {
    self.renderedFrameCount = 0;
    self.lastFrameCPUNs = 0;
    self.lastFrameTargetBudgetNs = OrenAVMMetalTargetBudgetNs(self.targetHzMilli);
    self.lastFrameVertexCount = 0;
    self.lastFrameTextRunCount = 0;
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

- (NSMutableData*)orenVerticesForFrame:(NSData*)frame
                            clearColor:(MTLClearColor*)clearColor
                              textRuns:(NSMutableArray<OrenAVMMetalTextRun*>*)textRuns {
    NSMutableData* vertices = [NSMutableData data];
    if (frame.length < 40) return vertices;
    const uint8_t* data = (const uint8_t*)frame.bytes;
    if (memcmp(data, "OGF0", 4) != 0 || data[4] != 1) return vertices;
    uint16_t headerLen = OrenAVMMetalReadU16LE(data + 6);
    if (headerLen < 40 || headerLen > frame.length) return vertices;
    uint32_t logicalW = OrenAVMMetalReadU32LE(data + 8);
    uint32_t logicalH = OrenAVMMetalReadU32LE(data + 12);
    uint32_t opCount = OrenAVMMetalReadU32LE(data + 20);
    if (logicalW == 0 || logicalH == 0) return vertices;

    size_t off = headerLen;
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
            OrenAVMMetalAppendRect(vertices, (float)x, (float)y, (float)w, (float)h,
                                   (float)logicalW, (float)logicalH, rgba);
        } else if (opcode == 3 && payloadLen == 24) {
            uint32_t x1 = OrenAVMMetalReadU32LE(payload);
            uint32_t y1 = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t x2 = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t y2 = OrenAVMMetalReadU32LE(payload + 12);
            uint32_t width = OrenAVMMetalReadU32LE(payload + 16);
            OrenAVMMetalAppendLine(vertices, (float)x1, (float)y1, (float)x2, (float)y2,
                                   (float)(width == 0 ? 1u : width),
                                   (float)logicalW, (float)logicalH, payload + 20);
        } else if (opcode == 4 && payloadLen == 20) {
            uint32_t cx = OrenAVMMetalReadU32LE(payload);
            uint32_t cy = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t radius = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t flags = OrenAVMMetalReadU32LE(payload + 12);
            OrenAVMMetalAppendCircle(vertices,
                                     (float)cx,
                                     (float)cy,
                                     (float)radius,
                                     (flags & 1u) != 0,
                                     (float)logicalW,
                                     (float)logicalH,
                                     payload + 16);
        } else if (opcode == 5 && payloadLen == 28) {
            uint32_t x1 = OrenAVMMetalReadU32LE(payload);
            uint32_t y1 = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t x2 = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t y2 = OrenAVMMetalReadU32LE(payload + 12);
            uint32_t x3 = OrenAVMMetalReadU32LE(payload + 16);
            uint32_t y3 = OrenAVMMetalReadU32LE(payload + 20);
            OrenAVMMetalAppendTriangle(vertices,
                                       (float)x1,
                                       (float)y1,
                                       (float)x2,
                                       (float)y2,
                                       (float)x3,
                                       (float)y3,
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
                                                                    x:(float)x
                                                                    y:(float)y
                                                                  rgba:payload + 8
                                                          logicalWidth:(float)logicalW
                                                         logicalHeight:(float)logicalH];
                if (run) [textRuns addObject:run];
            }
        }
        off += payloadLen;
    }
    return vertices;
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
    NSMutableData* vertices = [self orenVerticesForFrame:self.frameData
                                              clearColor:&clearColor
                                                textRuns:textRuns];
    self.lastFrameVertexCount = (uint32_t)(vertices.length / sizeof(OrenAVMMetalVertex));
    self.lastFrameTextRunCount = (uint32_t)textRuns.count;
    pass.colorAttachments[0].clearColor = clearColor;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> commandBuffer = [self.orenCommandQueue commandBuffer];
    if (!commandBuffer) return;
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    if (!encoder) return;
    if (encoder && self.orenPipelineState && vertices.length > 0) {
        [encoder setRenderPipelineState:self.orenPipelineState];
        [encoder setVertexBytes:vertices.bytes length:vertices.length atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                     vertexStart:0
                     vertexCount:vertices.length / sizeof(OrenAVMMetalVertex)];
    }
    if (encoder && self.orenTextPipelineState) {
        [encoder setRenderPipelineState:self.orenTextPipelineState];
        for (OrenAVMMetalTextRun* run in textRuns) {
            if (!run.texture || run.vertices.length == 0) continue;
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
