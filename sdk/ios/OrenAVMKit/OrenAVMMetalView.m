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

static uint16_t OrenAVMMetalReadU16LE(const uint8_t* p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t OrenAVMMetalReadU32LE(const uint8_t* p) {
    return (uint32_t)p[0] |
        ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) |
        ((uint32_t)p[3] << 24);
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

@interface OrenAVMMetalView () <MTKViewDelegate>
@property(nonatomic, strong, nullable) id<MTLCommandQueue> orenCommandQueue;
@property(nonatomic, strong, nullable) id<MTLRenderPipelineState> orenPipelineState;
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
    if (self.targetHzMilli == 0) self.targetHzMilli = 60000u;
    [self orenApplyFrameRate];
    if (self.device) {
        self.orenCommandQueue = [self.device newCommandQueue];
        [self orenBuildPipeline];
    }
    self.delegate = self;
}

- (void)setTargetHzMilli:(uint32_t)targetHzMilli {
    _targetHzMilli = targetHzMilli;
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
        "vertex O oren_vertex(uint vid [[vertex_id]], constant V* verts [[buffer(0)]]) {\n"
        "  O o; o.position = float4(verts[vid].pos, 0.0, 1.0); o.color = verts[vid].color; return o;\n"
        "}\n"
        "fragment float4 oren_fragment(O in [[stage_in]]) { return in.color; }\n";
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

- (NSMutableData*)orenVerticesForFrame:(NSData*)frame clearColor:(MTLClearColor*)clearColor {
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
        }
        off += payloadLen;
    }
    return vertices;
}

- (void)drawInMTKView:(MTKView*)view {
    (void)view;
    if (!self.device || !self.orenCommandQueue) return;
    (void)[self publishScreenStateWithError:nil];
    (void)[self reloadFrameWithError:nil];

    id<CAMetalDrawable> drawable = self.currentDrawable;
    MTLRenderPassDescriptor* pass = self.currentRenderPassDescriptor;
    if (!drawable || !pass) return;

    MTLClearColor clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    NSMutableData* vertices = [self orenVerticesForFrame:self.frameData clearColor:&clearColor];
    pass.colorAttachments[0].clearColor = clearColor;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> commandBuffer = [self.orenCommandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    if (encoder && self.orenPipelineState && vertices.length > 0) {
        [encoder setRenderPipelineState:self.orenPipelineState];
        [encoder setVertexBytes:vertices.bytes length:vertices.length atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                     vertexStart:0
                     vertexCount:vertices.length / sizeof(OrenAVMMetalVertex)];
    }
    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
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

- (void)orenSendTouches:(NSSet<UITouch*>*)touches kind:(uint8_t)kind {
    UITouch* touch = touches.anyObject;
    if (!touch) return;
    CGPoint p = [touch locationInView:self];
    NSError* error = nil;
    (void)[self sendPointerEventWithKind:kind
                                   point:p
                               pointerId:(uint32_t)touch.hash
                                   error:&error];
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self orenSendTouches:touches kind:1];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self orenSendTouches:touches kind:2];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self orenSendTouches:touches kind:3];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    [self orenSendTouches:touches kind:4];
}

@end

#endif
