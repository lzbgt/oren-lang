#import "OrenAVMKit.h"
#import "OrenAVMMetalGeometry.h"
#import "OrenAVMMetalResources.h"
#import "OrenAVMMetalText.h"

#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint32_t triangle;
    int64_t zsum;
} OrenAVMMetalTriangleOrder;

enum { OrenAVMMetalInlineTriangleOrderCapacity = 128 };

_Static_assert(sizeof(OrenAVMMetalTextVertex) == 16, "OrenAVMMetalTextVertex must match shader packed_float2+packed_float2");

typedef struct {
    BOOL enabled;
    MTLScissorRect rect;
} OrenAVMMetalScissorState;

static const NSUInteger OrenAVMMetalDefaultRetainedImagePixelLimit = 16u * 1024u * 1024u;
static const NSUInteger OrenAVMMetalDefaultRetainedImageCountLimit = 1024u;
static const NSUInteger OrenAVMMetalInlineVertexBytesLimit = 4096u;

static uint16_t OrenAVMMetalReadU16LE(const uint8_t* p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t OrenAVMMetalReadU32LE(const uint8_t* p) {
    return (uint32_t)p[0] |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static BOOL OrenAVMMetalSubrectInTexture(uint32_t sx, uint32_t sy, uint32_t sw, uint32_t sh, NSUInteger width, NSUInteger height) {
    return (uint64_t)sx + (uint64_t)sw <= (uint64_t)width &&
        (uint64_t)sy + (uint64_t)sh <= (uint64_t)height;
}

static BOOL OrenAVMMetalFrameDataIsValid(NSData* frame) {
    if (frame.length < 24) return NO;
    const uint8_t* data = (const uint8_t*)frame.bytes;
    if (memcmp(data, "OGF0", 4) != 0) return NO;
    uint8_t version = data[4];
    if (version != 0 && version != 1) return NO;
    uint16_t headerLen = version == 0 ? 24 : OrenAVMMetalReadU16LE(data + 6);
    if (headerLen < 24 || headerLen > frame.length) return NO;
    return OrenAVMMetalReadU32LE(data + 8) != 0 && OrenAVMMetalReadU32LE(data + 12) != 0;
}

static NSUInteger OrenAVMMetalFrameRunCapacity(NSData* frame) {
    if (frame.length < 40) return 0;
    const uint8_t* data = (const uint8_t*)frame.bytes;
    if (memcmp(data, "OGF0", 4) != 0 || data[4] != 1) return 0;
    uint16_t headerLen = OrenAVMMetalReadU16LE(data + 6);
    if (headerLen < 40 || headerLen > frame.length) return 0;
    uint32_t opCount = OrenAVMMetalReadU32LE(data + 20);
    NSUInteger maxRecordsByBytes = (frame.length - headerLen) / 4u;
    return (NSUInteger)opCount < maxRecordsByBytes ? (NSUInteger)opCount : maxRecordsByBytes;
}

static NSMutableArray* OrenAVMMetalEnsureRunArray(NSMutableArray** runs, NSUInteger capacity) {
    if (!runs) return nil;
    if (!*runs) *runs = [NSMutableArray arrayWithCapacity:capacity];
    return *runs;
}

static int64_t OrenAVMMetalMesh3DZSum(const uint8_t* tri) {
    return (int64_t)(int32_t)OrenAVMMetalReadU32LE(tri + 8) +
           (int64_t)(int32_t)OrenAVMMetalReadU32LE(tri + 20) +
           (int64_t)(int32_t)OrenAVMMetalReadU32LE(tri + 32);
}

static int64_t OrenAVMMetalMesh3DZSumModel(const uint8_t* tri, int32_t offset, uint32_t scaleMilli) {
    return (OrenAVMMetalMesh3DZSum(tri) * (int64_t)scaleMilli) / 1000 + (int64_t)offset * 3;
}

static BOOL OrenAVMMetalMesh3DZVisible(int64_t zsum, BOOL depthEnabled, int32_t nearZ, int32_t farZ) {
    if (!depthEnabled) return YES;
    return zsum >= (int64_t)nearZ * 3 && zsum <= (int64_t)farZ * 3;
}

static int OrenAVMMetalTriangleOrderCompare(const void* left, const void* right) {
    const OrenAVMMetalTriangleOrder* a = (const OrenAVMMetalTriangleOrder*)left;
    const OrenAVMMetalTriangleOrder* b = (const OrenAVMMetalTriangleOrder*)right;
    if (a->zsum > b->zsum) return -1;
    if (a->zsum < b->zsum) return 1;
    if (a->triangle < b->triangle) return -1;
    if (a->triangle > b->triangle) return 1;
    return 0;
}

static OrenAVMMetalTriangleOrder* OrenAVMMetalTriangleOrderBuffer(uint32_t triangleCount,
                                                                  OrenAVMMetalTriangleOrder* inlineOrder,
                                                                  uint32_t inlineCapacity,
                                                                  OrenAVMMetalTriangleOrder** heapStorage) {
    if (heapStorage) *heapStorage = NULL;
    if (triangleCount == 0) return NULL;
    if (inlineOrder && triangleCount <= inlineCapacity) return inlineOrder;
    if (!heapStorage || (NSUInteger)triangleCount > NSUIntegerMax / sizeof(OrenAVMMetalTriangleOrder)) return NULL;
    OrenAVMMetalTriangleOrder* bytes = (OrenAVMMetalTriangleOrder*)malloc((NSUInteger)triangleCount * sizeof(OrenAVMMetalTriangleOrder));
    if (!bytes) return NULL;
    *heapStorage = bytes;
    return bytes;
}

static void OrenAVMMetalSortTriangleOrder(OrenAVMMetalTriangleOrder* order, uint32_t count) {
    if (count > 1) qsort(order, count, sizeof(OrenAVMMetalTriangleOrder), OrenAVMMetalTriangleOrderCompare);
}

static int64_t OrenAVMMetalMesh3DIndexedZSumModel(const uint8_t* vertices,
                                                  const uint8_t* indices,
                                                  uint32_t triangle,
                                                  int32_t offset,
                                                  uint32_t scaleMilli) {
    const uint8_t* tri = indices + ((size_t)triangle * 12u);
    uint32_t i1 = OrenAVMMetalReadU32LE(tri);
    uint32_t i2 = OrenAVMMetalReadU32LE(tri + 4);
    uint32_t i3 = OrenAVMMetalReadU32LE(tri + 8);
    int64_t z = (int64_t)(int32_t)OrenAVMMetalReadU32LE(vertices + ((size_t)i1 * 12u) + 8) +
                (int64_t)(int32_t)OrenAVMMetalReadU32LE(vertices + ((size_t)i2 * 12u) + 8) +
                (int64_t)(int32_t)OrenAVMMetalReadU32LE(vertices + ((size_t)i3 * 12u) + 8);
    return (z * (int64_t)scaleMilli) / 1000 + (int64_t)offset * 3;
}

static float OrenAVMMetalMesh3DModelCoord(const uint8_t* p, int32_t offset, uint32_t scaleMilli) {
    int32_t v = (int32_t)OrenAVMMetalReadU32LE(p);
    return (float)(((int64_t)v * (int64_t)scaleMilli) / 1000 + (int64_t)offset);
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

static NSUInteger OrenAVMMetalInitialVertexBuilderCapacity(NSUInteger runCapacity) {
    const NSUInteger bytesPerSimpleRun = sizeof(OrenAVMMetalVertex) * 6u;
    const NSUInteger maxInitialBytes = 64u * 1024u;
    if (runCapacity == 0) return bytesPerSimpleRun;
    if (runCapacity > maxInitialBytes / bytesPerSimpleRun) return maxInitialBytes;
    return runCapacity * bytesPerSimpleRun;
}

static OrenAVMMetalVertexBuffer* OrenAVMMetalEnsureVertexBuilder(OrenAVMMetalVertexBuffer* vertices, NSUInteger runCapacity) {
    if (vertices && vertices->initialCapacity == 0) {
        OrenAVMMetalVertexBufferInit(vertices, OrenAVMMetalInitialVertexBuilderCapacity(runCapacity));
    }
    return vertices;
}

static void OrenAVMMetalFlushVertexRun(NSMutableArray<OrenAVMMetalVertexRun*>** runsRef,
                                       OrenAVMMetalVertexBuffer* verticesRef,
                                       NSUInteger runCapacity,
                                       OrenAVMMetalScissorState scissor,
                                       BOOL continueBuilding) {
    if (!verticesRef || verticesRef->byteLength == 0) {
        if (verticesRef && verticesRef->failed) {
            NSUInteger initialCapacity = verticesRef->initialCapacity;
            OrenAVMMetalVertexBufferFree(verticesRef);
            OrenAVMMetalVertexBufferInit(verticesRef, initialCapacity);
        }
        return;
    }
    NSUInteger vertexBytes = 0;
    uint8_t* vertices = OrenAVMMetalVertexBufferTakeBytes(verticesRef, &vertexBytes);
    if (!vertices || vertexBytes == 0) return;
    NSMutableArray<OrenAVMMetalVertexRun*>* runs =
        (NSMutableArray<OrenAVMMetalVertexRun*>*)OrenAVMMetalEnsureRunArray((NSMutableArray**)runsRef, runCapacity);
    OrenAVMMetalVertexRun* run = [[OrenAVMMetalVertexRun alloc] init];
    run.vertices = vertices;
    run.vertexBytes = vertexBytes;
    run.hasScissor = scissor.enabled;
    run.scissor = scissor.rect;
    [runs addObject:run];
    (void)continueBuilding;
}

static BOOL OrenAVMMetalBindVertexPayload(id<MTLRenderCommandEncoder> encoder,
                                          id<MTLDevice> device,
                                          NSMutableArray<id<MTLBuffer>>** transientBuffers,
                                          const void* bytes,
                                          NSUInteger length) {
    if (!encoder || !bytes || length == 0) return NO;
    if (length <= OrenAVMMetalInlineVertexBytesLimit) {
        [encoder setVertexBytes:bytes length:length atIndex:0];
        return YES;
    }
    id<MTLBuffer> buffer = [device newBufferWithBytes:bytes
                                               length:length
                                              options:MTLResourceStorageModeShared];
    if (!buffer) return NO;
    if (!transientBuffers) return NO;
    if (!*transientBuffers) *transientBuffers = [NSMutableArray array];
    if (!*transientBuffers) return NO;
    [*transientBuffers addObject:buffer];
    [encoder setVertexBuffer:buffer offset:0 atIndex:0];
    return YES;
}

@interface OrenAVMMetalView () <MTKViewDelegate> {
    CFMutableDictionaryRef _orenTouchIDs;
}
@property(nonatomic, strong, nullable) id<MTLCommandQueue> orenCommandQueue;
@property(nonatomic, strong, nullable) id<MTLRenderPipelineState> orenPipelineState;
@property(nonatomic, strong, nullable) id<MTLRenderPipelineState> orenTextPipelineState;
@property(nonatomic, strong) NSMutableDictionary<OrenAVMMetalTextCacheKey*, OrenAVMMetalTextCacheEntry*>* orenTextCache;
@property(nonatomic, strong) NSMutableArray<OrenAVMMetalTextCacheKey*>* orenTextCacheOrder;
@property(nonatomic, strong) OrenAVMMetalTextAttributeCache* orenTextAttributes;
@property(nonatomic) NSUInteger orenTextCachePixels;
@property(nonatomic, strong, nullable) OrenAVMMetalTextAtlas* orenTextAtlas;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, OrenAVMMetalTextResource*>* orenTextResources;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, OrenAVMMetalMesh2DResource*>* orenMeshes;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, OrenAVMMetalMesh3DResource*>* orenMeshes3D;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, NSNumber*>* orenMaterials3D;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, OrenAVMMetalModelResource*>* orenModels3D;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, OrenAVMMetalImageResource*>* orenImages;
@property(nonatomic, readwrite) NSUInteger retainedImagePixelCount;
@property(nonatomic) uint32_t orenFrameTickSequence;
@property(nonatomic) uint64_t orenLastFrameTickNs;
@property(nonatomic, readwrite) uint64_t renderedFrameCount;
@property(nonatomic, readwrite) uint64_t lastFrameCPUNs;
@property(nonatomic, readwrite) uint64_t lastFrameTargetBudgetNs;
@property(nonatomic, readwrite) uint32_t lastFrameVertexCount;
@property(nonatomic, readwrite) uint32_t lastFrameTextRunCount;
@property(nonatomic, readwrite) uint32_t lastFrameImageRunCount;
@property(nonatomic) uint32_t orenNextTouchID;
@property(nonatomic, strong) id orenGraphicsFrameObserverToken;
@property(nonatomic) BOOL orenFrameReloadScheduled;
@end

@implementation OrenAVMMetalView

- (instancetype)initWithRuntime:(OrenAVMRuntime*)runtime {
    self = [super initWithFrame:CGRectZero device:MTLCreateSystemDefaultDevice()];
    if (!self) return nil;
    [self orenConfigureMetalView];
    self.runtime = runtime;
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

- (void)orenAttachGraphicsFrameObserver {
    if (!self.runtime || self.orenGraphicsFrameObserverToken) return;
    __weak typeof(self) weakSelf = self;
    self.orenGraphicsFrameObserverToken = [self.runtime addGraphicsFrameHandler:^(uint32_t sequence, NSUInteger byteLength) {
        (void)sequence;
        (void)byteLength;
        __strong typeof(weakSelf) schedulingSelf = weakSelf;
        if (!schedulingSelf) return;
        @synchronized (schedulingSelf) {
            if (schedulingSelf.orenFrameReloadScheduled) return;
            schedulingSelf.orenFrameReloadScheduled = YES;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            @synchronized (strongSelf) {
                strongSelf.orenFrameReloadScheduled = NO;
            }
            (void)[strongSelf reloadFrameWithError:nil];
            [strongSelf setNeedsDisplay];
        });
    }];
}

- (void)setRuntime:(OrenAVMRuntime*)runtime {
    if (_runtime == runtime) return;
    if (_runtime && self.orenGraphicsFrameObserverToken) {
        [_runtime removeGraphicsFrameHandler:self.orenGraphicsFrameObserverToken];
        self.orenGraphicsFrameObserverToken = nil;
    }
    _runtime = runtime;
    [self orenAttachGraphicsFrameObserver];
}

- (void)dealloc {
    if (_runtime && self.orenGraphicsFrameObserverToken) {
        [_runtime removeGraphicsFrameHandler:self.orenGraphicsFrameObserverToken];
    }
    if (_orenTouchIDs) {
        CFRelease(_orenTouchIDs);
        _orenTouchIDs = NULL;
    }
}

- (void)orenConfigureMetalView {
    self.multipleTouchEnabled = YES;
    self.framebufferOnly = YES;
    self.paused = NO;
    self.enableSetNeedsDisplay = NO;
    self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    if (!self.orenTextCache) self.orenTextCache = [NSMutableDictionary dictionary];
    if (!self.orenTextCacheOrder) self.orenTextCacheOrder = [NSMutableArray array];
    if (!self.orenTextAttributes) self.orenTextAttributes = [[OrenAVMMetalTextAttributeCache alloc] init];
    if (!self.orenTextResources) self.orenTextResources = [NSMutableDictionary dictionary];
    if (!self.orenMeshes) self.orenMeshes = [NSMutableDictionary dictionary];
    if (!self.orenMeshes3D) self.orenMeshes3D = [NSMutableDictionary dictionary];
    if (!self.orenMaterials3D) self.orenMaterials3D = [NSMutableDictionary dictionary];
    if (!self.orenModels3D) self.orenModels3D = [NSMutableDictionary dictionary];
    if (!self.orenImages) self.orenImages = [NSMutableDictionary dictionary];
    if (!_orenTouchIDs) _orenTouchIDs = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
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
    if (![self.runtime hasGraphicsFrameWithError:error]) return YES;
    NSData* frame = [self.runtime getGraphicsFrameDataWithError:error];
    if (!frame) return NO;
    if (!OrenAVMMetalFrameDataIsValid(frame)) return YES;
    self.frameData = frame;
    return YES;
}

- (void)clearTextTextureCache {
    NSUInteger pixels = self.orenTextCachePixels;
    OrenAVMMetalClearTextTextureCache(self.orenTextCache, self.orenTextCacheOrder, &pixels);
    self.orenTextCachePixels = pixels;
    self.orenTextAtlas = nil;
}

- (void)clearImageTextureCache {
    [self.orenImages removeAllObjects];
    self.retainedImagePixelCount = 0;
}

- (NSUInteger)retainedImageCount {
    return self.orenImages.count;
}

- (BOOL)hasValidFrameData {
    return OrenAVMMetalFrameDataIsValid(self.frameData);
}

- (void)resetFrameMetrics {
    self.renderedFrameCount = 0;
    self.lastFrameCPUNs = 0;
    self.lastFrameTargetBudgetNs = OrenAVMMetalTargetBudgetNs(self.targetHzMilli);
    self.lastFrameVertexCount = 0;
    self.lastFrameTextRunCount = 0;
    self.lastFrameImageRunCount = 0;
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
    OrenAVMMetalImageResource* oldResource = self.orenImages[key];
    NSUInteger oldPixels = oldResource ? oldResource.pixels : 0;
    NSUInteger countAfter = oldResource ? self.orenImages.count : self.orenImages.count + 1u;
    NSUInteger retainedAfterOld = self.retainedImagePixelCount >= oldPixels ? self.retainedImagePixelCount - oldPixels : 0;
    if (pixels > NSUIntegerMax - retainedAfterOld) return;
    NSUInteger pixelAfter = retainedAfterOld + pixels;
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
    OrenAVMMetalImageResource* resource = [[OrenAVMMetalImageResource alloc] init];
    resource.texture = texture;
    resource.pixels = pixels;
    self.orenImages[key] = resource;
    self.retainedImagePixelCount = pixelAfter;
}

- (void)orenRemoveImageTextureWithID:(uint32_t)imageID {
    NSNumber* key = @(imageID);
    OrenAVMMetalImageResource* old = self.orenImages[key];
    if (old) {
        NSUInteger pixels = old.pixels;
        self.retainedImagePixelCount = self.retainedImagePixelCount > pixels ? self.retainedImagePixelCount - pixels : 0;
    }
    [self.orenImages removeObjectForKey:key];
}

- (OrenAVMMetalImageRun*)orenImageRunWithTexture:(id<MTLTexture>)texture
                                    textureWidth:(NSUInteger)textureWidth
                                   textureHeight:(NSUInteger)textureHeight
                                              sx:(uint32_t)sx
                                              sy:(uint32_t)sy
                                              sw:(uint32_t)sw
                                              sh:(uint32_t)sh
                                               x:(float)x
                                               y:(float)y
                                               w:(float)w
                                               h:(float)h
                                         opacity:(float)opacity
                                    logicalWidth:(float)logicalWidth
                                   logicalHeight:(float)logicalHeight {
    if (!texture || w <= 0.0f || h <= 0.0f || sw == 0 || sh == 0) return nil;
    if (!OrenAVMMetalSubrectInTexture(sx, sy, sw, sh, textureWidth, textureHeight)) return nil;
    float u0 = (float)sx / (float)textureWidth;
    float v0 = (float)sy / (float)textureHeight;
    float u1 = (float)((uint64_t)sx + (uint64_t)sw) / (float)textureWidth;
    float v1 = (float)((uint64_t)sy + (uint64_t)sh) / (float)textureHeight;
    OrenAVMMetalImageRun* run = [[OrenAVMMetalImageRun alloc] init];
    run.texture = texture;
    OrenAVMMetalWriteTextureQuad(run->vertices, x, y, w, h, logicalWidth, logicalHeight, u0, v0, u1, v1);
    run.opacity = opacity;
    return run;
}

- (NSArray<OrenAVMMetalVertexRun*>*)orenVertexRunsForFrame:(NSData*)frame
                                                 clearColor:(MTLClearColor*)clearColor
                                                  textRuns:(NSMutableArray<OrenAVMMetalTextRun*>**)textRuns
                                                 imageRuns:(NSMutableArray<OrenAVMMetalImageRun*>**)imageRuns
                                               runCapacity:(NSUInteger)runCapacity {
    NSMutableArray<OrenAVMMetalVertexRun*>* vertexRuns = nil;
    if (frame.length < 40) return @[];
    const uint8_t* data = (const uint8_t*)frame.bytes;
    if (memcmp(data, "OGF0", 4) != 0 || data[4] != 1) return @[];
    uint16_t headerLen = OrenAVMMetalReadU16LE(data + 6);
    if (headerLen < 40 || headerLen > frame.length) return @[];
    uint32_t logicalW = OrenAVMMetalReadU32LE(data + 8);
    uint32_t logicalH = OrenAVMMetalReadU32LE(data + 12);
    uint32_t opCount = OrenAVMMetalReadU32LE(data + 20);
    uint32_t drawableW = OrenAVMMetalReadU32LE(data + 28);
    uint32_t drawableH = OrenAVMMetalReadU32LE(data + 32);
    if (logicalW == 0 || logicalH == 0 || drawableW == 0 || drawableH == 0) return @[];

    OrenAVMMetalVertexBuffer vertices;
    OrenAVMMetalVertexBufferInit(&vertices, OrenAVMMetalInitialVertexBuilderCapacity(runCapacity));
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
    float opacity = 1.0f;
    float opacityStack[64];
    uint32_t opacityDepth = 0;
    BOOL depthEnabled = NO;
    int32_t nearZ = 0;
    int32_t farZ = 0;
    BOOL depthEnabledStack[64];
    int32_t nearZStack[64];
    int32_t farZStack[64];
    uint32_t cameraDepth = 0;
    uint8_t rgba[4];
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
            OrenAVMMetalRGBAWithOpacity(payload + 16, opacity, rgba);
            if (x == 0 && y == 0 && w >= logicalW && h >= logicalH && clearColor && opacity >= 0.999f) {
                *clearColor = MTLClearColorMake((double)rgba[0] / 255.0,
                                                (double)rgba[1] / 255.0,
                                                (double)rgba[2] / 255.0,
                                                (double)rgba[3] / 255.0);
            }
            OrenAVMMetalAppendRect(OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity), (float)x + tx, (float)y + ty, (float)w, (float)h,
                                   (float)logicalW, (float)logicalH, rgba);
        } else if (opcode == 16 && payloadLen == 16) {
            OrenAVMMetalFlushVertexRun(&vertexRuns, &vertices, runCapacity, clip, YES);
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
            OrenAVMMetalFlushVertexRun(&vertexRuns, &vertices, runCapacity, clip, YES);
            if (clipDepth > 0) clip = clipStack[--clipDepth];
        } else if (opcode == 18 && payloadLen == 8) {
            OrenAVMMetalFlushVertexRun(&vertexRuns, &vertices, runCapacity, clip, YES);
            if (transformDepth < 64) {
                txStack[transformDepth] = tx;
                tyStack[transformDepth] = ty;
                transformDepth++;
                tx += (float)(int32_t)OrenAVMMetalReadU32LE(payload);
                ty += (float)(int32_t)OrenAVMMetalReadU32LE(payload + 4);
            }
        } else if (opcode == 19 && payloadLen == 0) {
            OrenAVMMetalFlushVertexRun(&vertexRuns, &vertices, runCapacity, clip, YES);
            if (transformDepth > 0) {
                transformDepth--;
                tx = txStack[transformDepth];
                ty = tyStack[transformDepth];
            }
        } else if (opcode == 20 && payloadLen == 4) {
            OrenAVMMetalFlushVertexRun(&vertexRuns, &vertices, runCapacity, clip, YES);
            if (opacityDepth < 64) {
                opacityStack[opacityDepth++] = opacity;
                opacity *= (float)OrenAVMMetalReadU32LE(payload) / 1000.0f;
            }
        } else if (opcode == 21 && payloadLen == 0) {
            OrenAVMMetalFlushVertexRun(&vertexRuns, &vertices, runCapacity, clip, YES);
            if (opacityDepth > 0) opacity = opacityStack[--opacityDepth];
        } else if (opcode == 22 && payloadLen == 8) {
            OrenAVMMetalFlushVertexRun(&vertexRuns, &vertices, runCapacity, clip, YES);
            if (cameraDepth < 64) {
                depthEnabledStack[cameraDepth] = depthEnabled;
                nearZStack[cameraDepth] = nearZ;
                farZStack[cameraDepth] = farZ;
                cameraDepth++;
                depthEnabled = YES;
                nearZ = (int32_t)OrenAVMMetalReadU32LE(payload);
                farZ = (int32_t)OrenAVMMetalReadU32LE(payload + 4);
            }
        } else if (opcode == 23 && payloadLen == 0) {
            OrenAVMMetalFlushVertexRun(&vertexRuns, &vertices, runCapacity, clip, YES);
            if (cameraDepth > 0) {
                cameraDepth--;
                depthEnabled = depthEnabledStack[cameraDepth];
                nearZ = nearZStack[cameraDepth];
                farZ = farZStack[cameraDepth];
            }
        } else if (opcode == 3 && payloadLen == 24) {
            uint32_t x1 = OrenAVMMetalReadU32LE(payload);
            uint32_t y1 = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t x2 = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t y2 = OrenAVMMetalReadU32LE(payload + 12);
            uint32_t width = OrenAVMMetalReadU32LE(payload + 16);
            OrenAVMMetalRGBAWithOpacity(payload + 20, opacity, rgba);
            OrenAVMMetalAppendLine(OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity), (float)x1 + tx, (float)y1 + ty, (float)x2 + tx, (float)y2 + ty,
                                   (float)(width == 0 ? 1u : width),
                                   (float)logicalW, (float)logicalH, rgba);
        } else if (opcode == 6 && payloadLen == 24) {
            uint32_t x = OrenAVMMetalReadU32LE(payload);
            uint32_t y = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t w = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t h = OrenAVMMetalReadU32LE(payload + 12);
            uint32_t width = OrenAVMMetalReadU32LE(payload + 16);
            OrenAVMMetalRGBAWithOpacity(payload + 20, opacity, rgba);
            OrenAVMMetalAppendStrokeRect(OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity),
                                         (float)x + tx,
                                         (float)y + ty,
                                         (float)w,
                                         (float)h,
                                         (float)(width == 0 ? 1u : width),
                                         (float)logicalW,
                                         (float)logicalH,
                                         rgba);
        } else if (opcode == 9 && payloadLen == 32) {
            uint32_t x = OrenAVMMetalReadU32LE(payload);
            uint32_t y = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t w = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t h = OrenAVMMetalReadU32LE(payload + 12);
            uint32_t radius = OrenAVMMetalReadU32LE(payload + 16);
            uint32_t width = OrenAVMMetalReadU32LE(payload + 20);
            uint32_t flags = OrenAVMMetalReadU32LE(payload + 24);
            OrenAVMMetalRGBAWithOpacity(payload + 28, opacity, rgba);
            OrenAVMMetalAppendRoundRect(OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity),
                                        (float)x + tx,
                                        (float)y + ty,
                                        (float)w,
                                        (float)h,
                                        (float)radius,
                                        (float)(width == 0 ? 1u : width),
                                        (flags & 1u) != 0,
                                        (float)logicalW,
                                        (float)logicalH,
                                        rgba);
        } else if (opcode == 4 && payloadLen == 20) {
            uint32_t cx = OrenAVMMetalReadU32LE(payload);
            uint32_t cy = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t radius = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t flags = OrenAVMMetalReadU32LE(payload + 12);
            OrenAVMMetalRGBAWithOpacity(payload + 16, opacity, rgba);
            OrenAVMMetalAppendCircle(OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity),
                                     (float)cx + tx,
                                     (float)cy + ty,
                                     (float)radius,
                                     (flags & 1u) != 0,
                                     (float)logicalW,
                                     (float)logicalH,
                                     rgba);
        } else if (opcode == 7 && payloadLen == 28) {
            uint32_t x = OrenAVMMetalReadU32LE(payload);
            uint32_t y = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t w = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t h = OrenAVMMetalReadU32LE(payload + 12);
            uint32_t width = OrenAVMMetalReadU32LE(payload + 16);
            uint32_t flags = OrenAVMMetalReadU32LE(payload + 20);
            OrenAVMMetalRGBAWithOpacity(payload + 24, opacity, rgba);
            OrenAVMMetalAppendEllipse(OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity),
                                      (float)x + tx,
                                      (float)y + ty,
                                      (float)w,
                                      (float)h,
                                      (float)(width == 0 ? 1u : width),
                                      (flags & 1u) != 0,
                                      (float)logicalW,
                                      (float)logicalH,
                                      rgba);
        } else if (opcode == 8 && payloadLen >= 28 && ((payloadLen - 12) % 8) == 0) {
            uint32_t width = OrenAVMMetalReadU32LE(payload);
            uint32_t pointCount = OrenAVMMetalReadU32LE(payload + 4);
            OrenAVMMetalRGBAWithOpacity(payload + 8, opacity, rgba);
            const uint8_t* points = payload + 12;
            if (pointCount == ((uint32_t)payloadLen - 12u) / 8u && pointCount >= 2) {
                uint32_t lastX = OrenAVMMetalReadU32LE(points);
                uint32_t lastY = OrenAVMMetalReadU32LE(points + 4);
                for (uint32_t pi = 1; pi < pointCount; pi++) {
                    const uint8_t* point = points + ((size_t)pi * 8u);
                    uint32_t x = OrenAVMMetalReadU32LE(point);
                    uint32_t y = OrenAVMMetalReadU32LE(point + 4);
                    OrenAVMMetalAppendLine(OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity),
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
            OrenAVMMetalRGBAWithOpacity(payload + 24, opacity, rgba);
            OrenAVMMetalAppendTriangle(OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity),
                                       (float)x1 + tx,
                                       (float)y1 + ty,
                                       (float)x2 + tx,
                                       (float)y2 + ty,
                                       (float)x3 + tx,
                                       (float)y3 + ty,
                                       (float)logicalW,
                                       (float)logicalH,
                                       rgba);
        } else if (opcode == 10 && payloadLen >= 32 && ((payloadLen - 8) % 24) == 0) {
            uint32_t triangleCount = OrenAVMMetalReadU32LE(payload);
            OrenAVMMetalRGBAWithOpacity(payload + 4, opacity, rgba);
            const uint8_t* tris = payload + 8;
            if (triangleCount == ((uint32_t)payloadLen - 8u) / 24u) {
                for (uint32_t ti = 0; ti < triangleCount; ti++) {
                    const uint8_t* tri = tris + ((size_t)ti * 24u);
                    OrenAVMMetalAppendTriangle(OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity),
                                               (float)OrenAVMMetalReadU32LE(tri) + tx,
                                               (float)OrenAVMMetalReadU32LE(tri + 4) + ty,
                                               (float)OrenAVMMetalReadU32LE(tri + 8) + tx,
                                               (float)OrenAVMMetalReadU32LE(tri + 12) + ty,
                                               (float)OrenAVMMetalReadU32LE(tri + 16) + tx,
                                               (float)OrenAVMMetalReadU32LE(tri + 20) + ty,
                                               (float)logicalW,
                                               (float)logicalH,
                                               rgba);
                }
            }
        } else if (opcode == 80 && payloadLen >= 36 && ((payloadLen - 12) % 24) == 0) {
            uint32_t meshID = OrenAVMMetalReadU32LE(payload);
            uint32_t triangleCount = OrenAVMMetalReadU32LE(payload + 8);
            if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 12u) / 24u) {
                OrenAVMMetalMesh2DResource* mesh = [[OrenAVMMetalMesh2DResource alloc] init];
                mesh.rgbaValue = OrenAVMMetalReadU32LE(payload + 4);
                mesh.triangleBytes = (NSUInteger)payloadLen - 12u;
                mesh.triangles = OrenAVMMetalCopyPayloadBytes(payload + 12, mesh.triangleBytes);
                if (!mesh.triangles) {
                    off += payloadLen;
                    continue;
                }
                mesh.triangleCount = triangleCount;
                self.orenMeshes[@(meshID)] = mesh;
            }
        } else if (opcode == 81 && payloadLen == 4) {
            OrenAVMMetalMesh2DResource* mesh = self.orenMeshes[@(OrenAVMMetalReadU32LE(payload))];
            const uint8_t* tris = mesh.triangles;
            if (tris && mesh.triangleCount == mesh.triangleBytes / 24u) {
                OrenAVMMetalRGBAValueWithOpacity(mesh.rgbaValue, opacity, rgba);
                for (uint32_t ti = 0; ti < mesh.triangleCount; ti++) {
                    const uint8_t* tri = tris + ((size_t)ti * 24u);
                    OrenAVMMetalAppendTriangle(OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity),
                                               (float)OrenAVMMetalReadU32LE(tri) + tx,
                                               (float)OrenAVMMetalReadU32LE(tri + 4) + ty,
                                               (float)OrenAVMMetalReadU32LE(tri + 8) + tx,
                                               (float)OrenAVMMetalReadU32LE(tri + 12) + ty,
                                               (float)OrenAVMMetalReadU32LE(tri + 16) + tx,
                                               (float)OrenAVMMetalReadU32LE(tri + 20) + ty,
                                               (float)logicalW,
                                               (float)logicalH,
                                               rgba);
                }
            }
        } else if (opcode == 82 && payloadLen == 4) {
            [self.orenMeshes removeObjectForKey:@(OrenAVMMetalReadU32LE(payload))];
        } else if (opcode == 83 && payloadLen >= 48 && ((payloadLen - 12) % 36) == 0) {
            uint32_t meshID = OrenAVMMetalReadU32LE(payload);
            uint32_t triangleCount = OrenAVMMetalReadU32LE(payload + 8);
            if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 12u) / 36u) {
                OrenAVMMetalMesh3DResource* mesh = [[OrenAVMMetalMesh3DResource alloc] init];
                mesh.rgbaValue = OrenAVMMetalReadU32LE(payload + 4);
                mesh.hasRGBA = YES;
                mesh.triangleBytes = (NSUInteger)payloadLen - 12u;
                mesh.triangles = OrenAVMMetalCopyPayloadBytes(payload + 12, mesh.triangleBytes);
                if (!mesh.triangles) {
                    off += payloadLen;
                    continue;
                }
                mesh.triangleCount = triangleCount;
                mesh.stride = 36u;
                self.orenMeshes3D[@(meshID)] = mesh;
            }
        } else if ((opcode == 84 && payloadLen == 4) || (opcode == 87 && payloadLen == 20) ||
                   (opcode == 90 && payloadLen == 8) || (opcode == 91 && payloadLen == 24) ||
                   (opcode == 94 && payloadLen == 4)) {
            uint32_t meshID = OrenAVMMetalReadU32LE(payload);
            uint32_t materialID = 0;
            int32_t modelX = 0;
            int32_t modelY = 0;
            int32_t modelZ = 0;
            uint32_t scaleMilli = 1000u;
            if (opcode == 94) {
                OrenAVMMetalModelResource* model = self.orenModels3D[@(meshID)];
                if (!model) {
                    off += payloadLen;
                    continue;
                }
                meshID = model.meshID;
                materialID = model.materialID;
                modelX = model.x;
                modelY = model.y;
                modelZ = model.z;
                scaleMilli = model.scaleMilli;
            }
            OrenAVMMetalMesh3DResource* mesh = self.orenMeshes3D[@(meshID)];
            NSNumber* materialRGBAValue = nil;
            if (opcode == 90 || opcode == 91) {
                materialID = OrenAVMMetalReadU32LE(payload + 4);
            }
            if (materialID != 0) {
                materialRGBAValue = self.orenMaterials3D[@(materialID)];
                if (!materialRGBAValue) {
                    off += payloadLen;
                    continue;
                }
            }
            uint32_t materialRGBA = materialRGBAValue ? materialRGBAValue.unsignedIntValue : mesh.rgbaValue;
            const uint8_t* tris = mesh.triangles;
            const uint8_t* verts = mesh.vertices;
            const uint8_t* idx = mesh.indices;
            uint32_t meshStride = mesh.stride == 0 ? 36u : mesh.stride;
            if (opcode == 87) {
                modelX = (int32_t)OrenAVMMetalReadU32LE(payload + 4);
                modelY = (int32_t)OrenAVMMetalReadU32LE(payload + 8);
                modelZ = (int32_t)OrenAVMMetalReadU32LE(payload + 12);
                scaleMilli = OrenAVMMetalReadU32LE(payload + 16);
            } else if (opcode == 91) {
                modelX = (int32_t)OrenAVMMetalReadU32LE(payload + 8);
                modelY = (int32_t)OrenAVMMetalReadU32LE(payload + 12);
                modelZ = (int32_t)OrenAVMMetalReadU32LE(payload + 16);
                scaleMilli = OrenAVMMetalReadU32LE(payload + 20);
            }
            if (verts && idx && mesh.hasRGBA && scaleMilli != 0 && mesh.indexCount == mesh.indexBytes / 4u) {
                uint32_t triangleTotal = mesh.indexCount / 3u;
                OrenAVMMetalTriangleOrder inlineOrder[OrenAVMMetalInlineTriangleOrderCapacity];
                OrenAVMMetalTriangleOrder* heapOrder = NULL;
                OrenAVMMetalTriangleOrder* order = OrenAVMMetalTriangleOrderBuffer(triangleTotal,
                                                                                   inlineOrder,
                                                                                   OrenAVMMetalInlineTriangleOrderCapacity,
                                                                                   &heapOrder);
                if (triangleTotal != 0 && !order) continue;
                uint32_t visibleTotal = 0;
                for (uint32_t ti = 0; ti < triangleTotal; ti++) {
                    int64_t z = OrenAVMMetalMesh3DIndexedZSumModel(verts, idx, ti, modelZ, scaleMilli);
                    if (!OrenAVMMetalMesh3DZVisible(z, depthEnabled, nearZ, farZ)) continue;
                    order[visibleTotal++] = (OrenAVMMetalTriangleOrder){ti, z};
                }
                OrenAVMMetalSortTriangleOrder(order, visibleTotal);
                for (uint32_t di = 0; di < visibleTotal; di++) {
                    uint32_t best = order[di].triangle;
                    const uint8_t* tri = idx + ((size_t)best * 12u);
                    const uint8_t* v1 = verts + ((size_t)OrenAVMMetalReadU32LE(tri) * 12u);
                    const uint8_t* v2 = verts + ((size_t)OrenAVMMetalReadU32LE(tri + 4) * 12u);
                    const uint8_t* v3 = verts + ((size_t)OrenAVMMetalReadU32LE(tri + 8) * 12u);
                    OrenAVMMetalRGBAValueWithOpacity(materialRGBA, opacity, rgba);
                    OrenAVMMetalAppendTriangle(OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity),
                                               OrenAVMMetalMesh3DModelCoord(v1, modelX, scaleMilli) + tx,
                                               OrenAVMMetalMesh3DModelCoord(v1 + 4, modelY, scaleMilli) + ty,
                                               OrenAVMMetalMesh3DModelCoord(v2, modelX, scaleMilli) + tx,
                                               OrenAVMMetalMesh3DModelCoord(v2 + 4, modelY, scaleMilli) + ty,
                                               OrenAVMMetalMesh3DModelCoord(v3, modelX, scaleMilli) + tx,
                                               OrenAVMMetalMesh3DModelCoord(v3 + 4, modelY, scaleMilli) + ty,
                                               (float)logicalW,
                                               (float)logicalH,
                                               rgba);
                }
                free(heapOrder);
            } else if (tris && scaleMilli != 0 && (meshStride == 36u || meshStride == 40u) && mesh.triangleCount == mesh.triangleBytes / meshStride) {
                uint32_t triangleTotal = mesh.triangleCount;
                OrenAVMMetalTriangleOrder inlineOrder[OrenAVMMetalInlineTriangleOrderCapacity];
                OrenAVMMetalTriangleOrder* heapOrder = NULL;
                OrenAVMMetalTriangleOrder* order = OrenAVMMetalTriangleOrderBuffer(triangleTotal,
                                                                                   inlineOrder,
                                                                                   OrenAVMMetalInlineTriangleOrderCapacity,
                                                                                   &heapOrder);
                if (triangleTotal != 0 && !order) continue;
                uint32_t visibleTotal = 0;
                for (uint32_t ti = 0; ti < triangleTotal; ti++) {
                    int64_t z = OrenAVMMetalMesh3DZSumModel(tris + ((size_t)ti * meshStride), modelZ, scaleMilli);
                    if (!OrenAVMMetalMesh3DZVisible(z, depthEnabled, nearZ, farZ)) continue;
                    order[visibleTotal++] = (OrenAVMMetalTriangleOrder){ti, z};
                }
                OrenAVMMetalSortTriangleOrder(order, visibleTotal);
                for (uint32_t di = 0; di < visibleTotal; di++) {
                    uint32_t best = order[di].triangle;
                    const uint8_t* tri = tris + ((size_t)best * meshStride);
                    if (materialRGBAValue) {
                        OrenAVMMetalRGBAValueWithOpacity(materialRGBA, opacity, rgba);
                    } else if (meshStride == 40u) {
                        OrenAVMMetalRGBAWithOpacity(tri + 36, opacity, rgba);
                    } else if (mesh.hasRGBA) {
                        OrenAVMMetalRGBAValueWithOpacity(mesh.rgbaValue, opacity, rgba);
                    } else {
                        continue;
                    }
                    OrenAVMMetalAppendTriangle(OrenAVMMetalEnsureVertexBuilder(&vertices, runCapacity),
                                               OrenAVMMetalMesh3DModelCoord(tri, modelX, scaleMilli) + tx,
                                               OrenAVMMetalMesh3DModelCoord(tri + 4, modelY, scaleMilli) + ty,
                                               OrenAVMMetalMesh3DModelCoord(tri + 12, modelX, scaleMilli) + tx,
                                               OrenAVMMetalMesh3DModelCoord(tri + 16, modelY, scaleMilli) + ty,
                                               OrenAVMMetalMesh3DModelCoord(tri + 24, modelX, scaleMilli) + tx,
                                               OrenAVMMetalMesh3DModelCoord(tri + 28, modelY, scaleMilli) + ty,
                                               (float)logicalW,
                                               (float)logicalH,
                                               rgba);
                }
                free(heapOrder);
            }
        } else if (opcode == 85 && payloadLen == 4) {
            [self.orenMeshes3D removeObjectForKey:@(OrenAVMMetalReadU32LE(payload))];
        } else if (opcode == 89 && payloadLen == 8) {
            uint32_t materialID = OrenAVMMetalReadU32LE(payload);
            if (materialID != 0) self.orenMaterials3D[@(materialID)] = @(OrenAVMMetalReadU32LE(payload + 4));
        } else if (opcode == 92 && payloadLen == 4) {
            [self.orenMaterials3D removeObjectForKey:@(OrenAVMMetalReadU32LE(payload))];
        } else if (opcode == 93 && payloadLen == 28) {
            uint32_t modelID = OrenAVMMetalReadU32LE(payload);
            uint32_t meshID = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t scaleMilli = OrenAVMMetalReadU32LE(payload + 24);
            if (modelID != 0 && meshID != 0 && scaleMilli != 0) {
                OrenAVMMetalModelResource* model = [[OrenAVMMetalModelResource alloc] init];
                model.meshID = meshID;
                model.materialID = OrenAVMMetalReadU32LE(payload + 8);
                model.x = (int32_t)OrenAVMMetalReadU32LE(payload + 12);
                model.y = (int32_t)OrenAVMMetalReadU32LE(payload + 16);
                model.z = (int32_t)OrenAVMMetalReadU32LE(payload + 20);
                model.scaleMilli = scaleMilli;
                self.orenModels3D[@(modelID)] = model;
            }
        } else if (opcode == 95 && payloadLen == 4) {
            [self.orenModels3D removeObjectForKey:@(OrenAVMMetalReadU32LE(payload))];
        } else if (opcode == 86 && payloadLen >= 48 && ((payloadLen - 8) % 40) == 0) {
            uint32_t meshID = OrenAVMMetalReadU32LE(payload);
            uint32_t triangleCount = OrenAVMMetalReadU32LE(payload + 4);
            if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 8u) / 40u) {
                OrenAVMMetalMesh3DResource* mesh = [[OrenAVMMetalMesh3DResource alloc] init];
                mesh.triangleBytes = (NSUInteger)payloadLen - 8u;
                mesh.triangles = OrenAVMMetalCopyPayloadBytes(payload + 8, mesh.triangleBytes);
                if (!mesh.triangles) {
                    off += payloadLen;
                    continue;
                }
                mesh.triangleCount = triangleCount;
                mesh.stride = 40u;
                self.orenMeshes3D[@(meshID)] = mesh;
            }
        } else if (opcode == 88 && payloadLen >= 64) {
            uint32_t meshID = OrenAVMMetalReadU32LE(payload);
            uint32_t vertexCount = OrenAVMMetalReadU32LE(payload + 8);
            uint32_t indexCount = OrenAVMMetalReadU32LE(payload + 12);
            size_t vertexBytes = (size_t)vertexCount * 12u;
            size_t indexBytes = (size_t)indexCount * 4u;
            BOOL indicesOK = meshID != 0 && vertexCount >= 3u && indexCount >= 3u && indexCount % 3u == 0 &&
                16u + vertexBytes + indexBytes == (size_t)payloadLen;
            for (uint32_t ii = 0; indicesOK && ii < indexCount; ii++) {
                if (OrenAVMMetalReadU32LE(payload + 16 + vertexBytes + ((size_t)ii * 4u)) >= vertexCount) {
                    indicesOK = NO;
                }
            }
            if (indicesOK) {
                OrenAVMMetalMesh3DResource* mesh = [[OrenAVMMetalMesh3DResource alloc] init];
                mesh.rgbaValue = OrenAVMMetalReadU32LE(payload + 4);
                mesh.hasRGBA = YES;
                mesh.vertexBytes = vertexBytes;
                mesh.indexBytes = indexBytes;
                mesh.vertices = OrenAVMMetalCopyPayloadBytes(payload + 16, mesh.vertexBytes);
                mesh.indices = OrenAVMMetalCopyPayloadBytes(payload + 16 + vertexBytes, mesh.indexBytes);
                if (!mesh.vertices || !mesh.indices) {
                    off += payloadLen;
                    continue;
                }
                mesh.indexCount = indexCount;
                self.orenMeshes3D[@(meshID)] = mesh;
            }
        } else if (opcode == 2 && payloadLen >= 16) {
            uint32_t x = OrenAVMMetalReadU32LE(payload);
            uint32_t y = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t textLen = OrenAVMMetalReadU32LE(payload + 12);
            if (textLen == (uint32_t)payloadLen - 16u) {
                NSString* text = [[NSString alloc] initWithBytes:payload + 16
                                                          length:(NSUInteger)textLen
                                                        encoding:NSUTF8StringEncoding];
                NSUInteger textCachePixels = self.orenTextCachePixels;
                OrenAVMMetalTextAtlas* textAtlas = self.orenTextAtlas;
                OrenAVMMetalTextRun* run = OrenAVMMetalCreateTextRun(self.device,
                                                                     self.window.screen,
                                                                     &textAtlas,
                                                                     self.orenTextCache,
                                                                     self.orenTextCacheOrder,
                                                                     self.orenTextAttributes,
                                                                     &textCachePixels,
                                                                     text,
                                                                     (float)x + tx,
                                                                     (float)y + ty,
                                                                     payload + 8,
                                                                     opacity,
                                                                     (float)logicalW,
                                                                     (float)logicalH);
                self.orenTextCachePixels = textCachePixels;
                self.orenTextAtlas = textAtlas;
                if (run) {
                    run.hasScissor = clip.enabled;
                    run.scissor = clip.rect;
                    [OrenAVMMetalEnsureRunArray((NSMutableArray**)textRuns, runCapacity) addObject:run];
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
                    resource.rgbaValue = OrenAVMMetalReadU32LE(payload + 4);
                    self.orenTextResources[@(textID)] = resource;
                }
            }
        } else if (opcode == 69 && payloadLen == 12) {
            uint32_t textID = OrenAVMMetalReadU32LE(payload);
            uint32_t x = OrenAVMMetalReadU32LE(payload + 4);
            uint32_t y = OrenAVMMetalReadU32LE(payload + 8);
            OrenAVMMetalTextResource* resource = self.orenTextResources[@(textID)];
            if (resource.text) {
                uint8_t textRGBA[4];
                OrenAVMMetalRGBAValueBytes(resource.rgbaValue, textRGBA);
                NSUInteger textCachePixels = self.orenTextCachePixels;
                OrenAVMMetalTextAtlas* textAtlas = self.orenTextAtlas;
                OrenAVMMetalTextRun* run = OrenAVMMetalCreateTextRun(self.device,
                                                                     self.window.screen,
                                                                     &textAtlas,
                                                                     self.orenTextCache,
                                                                     self.orenTextCacheOrder,
                                                                     self.orenTextAttributes,
                                                                     &textCachePixels,
                                                                     resource.text,
                                                                     (float)x + tx,
                                                                     (float)y + ty,
                                                                     textRGBA,
                                                                     opacity,
                                                                     (float)logicalW,
                                                                     (float)logicalH);
                self.orenTextCachePixels = textCachePixels;
                self.orenTextAtlas = textAtlas;
                if (run) {
                    run.hasScissor = clip.enabled;
                    run.scissor = clip.rect;
                    [OrenAVMMetalEnsureRunArray((NSMutableArray**)textRuns, runCapacity) addObject:run];
                }
            }
        } else if (opcode == 72 && payloadLen >= 16 && ((payloadLen - 8) % 8) == 0) {
            uint32_t textID = OrenAVMMetalReadU32LE(payload);
            uint32_t posCount = OrenAVMMetalReadU32LE(payload + 4);
            OrenAVMMetalTextResource* resource = self.orenTextResources[@(textID)];
            if (resource.text && posCount == ((uint32_t)payloadLen - 8u) / 8u) {
                uint8_t textRGBA[4];
                OrenAVMMetalRGBAValueBytes(resource.rgbaValue, textRGBA);
                NSUInteger textCachePixels = self.orenTextCachePixels;
                OrenAVMMetalTextAtlas* textAtlas = self.orenTextAtlas;
                OrenAVMMetalTextRun* run = OrenAVMMetalCreateTextBatchRun(self.device,
                                                                          self.window.screen,
                                                                          &textAtlas,
                                                                          self.orenTextCache,
                                                                          self.orenTextCacheOrder,
                                                                          self.orenTextAttributes,
                                                                          &textCachePixels,
                                                                          resource.text,
                                                                          payload + 8,
                                                                          posCount,
                                                                          tx,
                                                                          ty,
                                                                          textRGBA,
                                                                          opacity,
                                                                          (float)logicalW,
                                                                          (float)logicalH);
                self.orenTextCachePixels = textCachePixels;
                self.orenTextAtlas = textAtlas;
                if (run) {
                    run.hasScissor = clip.enabled;
                    run.scissor = clip.rect;
                    [OrenAVMMetalEnsureRunArray((NSMutableArray**)textRuns, runCapacity) addObject:run];
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
            id<MTLTexture> texture = self.orenImages[@(imageID)].texture;
            if (texture) {
                NSUInteger textureWidth = texture.width;
                NSUInteger textureHeight = texture.height;
                OrenAVMMetalImageRun* run = [self orenImageRunWithTexture:texture
                                                              textureWidth:textureWidth
                                                             textureHeight:textureHeight
                                                                        sx:0
                                                                        sy:0
                                                                        sw:(uint32_t)textureWidth
                                                                        sh:(uint32_t)textureHeight
                                                                         x:(float)x + tx
                                                                         y:(float)y + ty
                                                                         w:(float)w
                                                                         h:(float)h
                                                                   opacity:opacity
                                                              logicalWidth:(float)logicalW
                                                             logicalHeight:(float)logicalH];
                if (run) {
                    run.hasScissor = clip.enabled;
                    run.scissor = clip.rect;
                    [OrenAVMMetalEnsureRunArray((NSMutableArray**)imageRuns, runCapacity) addObject:run];
                }
            }
        } else if (opcode == 66 && payloadLen == 4) {
            uint32_t imageID = OrenAVMMetalReadU32LE(payload);
            [self orenRemoveImageTextureWithID:imageID];
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
            id<MTLTexture> texture = self.orenImages[@(imageID)].texture;
            if (texture) {
                NSUInteger textureWidth = texture.width;
                NSUInteger textureHeight = texture.height;
                OrenAVMMetalImageRun* run = [self orenImageRunWithTexture:texture
                                                              textureWidth:textureWidth
                                                             textureHeight:textureHeight
                                                                        sx:sx
                                                                        sy:sy
                                                                        sw:sw
                                                                        sh:sh
                                                                         x:(float)x + tx
                                                                         y:(float)y + ty
                                                                         w:(float)w
                                                                         h:(float)h
                                                                   opacity:opacity
                                                              logicalWidth:(float)logicalW
                                                             logicalHeight:(float)logicalH];
                if (run) {
                    run.hasScissor = clip.enabled;
                    run.scissor = clip.rect;
                    [OrenAVMMetalEnsureRunArray((NSMutableArray**)imageRuns, runCapacity) addObject:run];
                }
            }
        } else if (opcode == 71 && payloadLen >= 40 && ((payloadLen - 8) % 32) == 0) {
            uint32_t imageID = OrenAVMMetalReadU32LE(payload);
            uint32_t rectCount = OrenAVMMetalReadU32LE(payload + 4);
            if (rectCount == ((uint32_t)payloadLen - 8u) / 32u) {
                id<MTLTexture> texture = self.orenImages[@(imageID)].texture;
                if (texture) {
                    NSUInteger textureWidth = texture.width;
                    NSUInteger textureHeight = texture.height;
                    for (uint32_t ri = 0; ri < rectCount; ri++) {
                        const uint8_t* r = payload + 8 + ((size_t)ri * 32u);
                        OrenAVMMetalImageRun* run = [self orenImageRunWithTexture:texture
                                                                      textureWidth:textureWidth
                                                                     textureHeight:textureHeight
                                                                                sx:OrenAVMMetalReadU32LE(r)
                                                                                sy:OrenAVMMetalReadU32LE(r + 4)
                                                                                sw:OrenAVMMetalReadU32LE(r + 8)
                                                                                sh:OrenAVMMetalReadU32LE(r + 12)
                                                                                 x:(float)OrenAVMMetalReadU32LE(r + 16) + tx
                                                                                 y:(float)OrenAVMMetalReadU32LE(r + 20) + ty
                                                                                 w:(float)OrenAVMMetalReadU32LE(r + 24)
                                                                                 h:(float)OrenAVMMetalReadU32LE(r + 28)
                                                                           opacity:opacity
                                                                      logicalWidth:(float)logicalW
                                                                     logicalHeight:(float)logicalH];
                        if (run) {
                            run.hasScissor = clip.enabled;
                            run.scissor = clip.rect;
                            [OrenAVMMetalEnsureRunArray((NSMutableArray**)imageRuns, runCapacity) addObject:run];
                        }
                    }
                }
            }
        }
        off += payloadLen;
    }
    OrenAVMMetalFlushVertexRun(&vertexRuns, &vertices, runCapacity, clip, NO);
    OrenAVMMetalVertexBufferFree(&vertices);
    return vertexRuns ?: @[];
}

- (NSArray<OrenAVMMetalVertexRun*>*)orenPrepareCurrentFrameWithClearColor:(MTLClearColor*)clearColorOut
                                                                imageRuns:(NSArray<OrenAVMMetalImageRun*>**)imageRunsOut
                                                                 textRuns:(NSArray<OrenAVMMetalTextRun*>**)textRunsOut {
    MTLClearColor clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    NSUInteger runCapacity = OrenAVMMetalFrameRunCapacity(self.frameData);
    NSMutableArray<OrenAVMMetalTextRun*>* textRuns = nil;
    NSMutableArray<OrenAVMMetalImageRun*>* imageRuns = nil;
    NSArray<OrenAVMMetalVertexRun*>* vertexRuns = [self orenVertexRunsForFrame:self.frameData
                                                                    clearColor:&clearColor
                                                                      textRuns:&textRuns
                                                                     imageRuns:&imageRuns
                                                                   runCapacity:runCapacity];
    NSArray<OrenAVMMetalTextRun*>* coalescedTextRuns = textRuns ? OrenAVMMetalCoalesceTextRuns(textRuns) : @[];
    uint32_t vertexCount = 0;
    for (OrenAVMMetalVertexRun* run in vertexRuns) {
        vertexCount += (uint32_t)(run.vertexBytes / sizeof(OrenAVMMetalVertex));
    }
    self.lastFrameVertexCount = vertexCount;
    self.lastFrameTextRunCount = (uint32_t)coalescedTextRuns.count;
    self.lastFrameImageRunCount = (uint32_t)imageRuns.count;
    if (clearColorOut) *clearColorOut = clearColor;
    if (imageRunsOut) *imageRunsOut = imageRuns ?: @[];
    if (textRunsOut) *textRunsOut = coalescedTextRuns;
    return vertexRuns;
}

- (BOOL)prepareFrameResourcesWithError:(NSError**)error {
    if (!OrenAVMMetalFrameDataIsValid(self.frameData) && self.runtime && ![self reloadFrameWithError:error]) return NO;
    if (!OrenAVMMetalFrameDataIsValid(self.frameData)) {
        return OrenAVMMetalAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                       @"metal view has no frame data");
    }
    uint64_t cpuStartNs = OrenAVMMetalNowNs();
    (void)[self orenPrepareCurrentFrameWithClearColor:NULL imageRuns:NULL textRuns:NULL];
    self.lastFrameCPUNs = OrenAVMMetalNowNs() - cpuStartNs;
    self.lastFrameTargetBudgetNs = OrenAVMMetalTargetBudgetNs(self.targetHzMilli);
    return YES;
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
    if (!drawable || !pass) {
        (void)[self prepareFrameResourcesWithError:nil];
        return;
    }

    MTLClearColor clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    NSArray<OrenAVMMetalImageRun*>* imageRuns = nil;
    NSArray<OrenAVMMetalTextRun*>* textRuns = nil;
    NSArray<OrenAVMMetalVertexRun*>* vertexRuns = [self orenPrepareCurrentFrameWithClearColor:&clearColor
                                                                                   imageRuns:&imageRuns
                                                                                    textRuns:&textRuns];
    pass.colorAttachments[0].clearColor = clearColor;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> commandBuffer = [self.orenCommandQueue commandBuffer];
    if (!commandBuffer) return;
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    if (!encoder) return;
    NSMutableArray<id<MTLBuffer>>* transientVertexBuffers = nil;
    MTLScissorRect fullScissor = (MTLScissorRect){0, 0, (NSUInteger)drawable.texture.width, (NSUInteger)drawable.texture.height};
    if (encoder && self.orenPipelineState) {
        [encoder setRenderPipelineState:self.orenPipelineState];
        for (OrenAVMMetalVertexRun* run in vertexRuns) {
            if (!run.vertices || run.vertexBytes == 0) continue;
            MTLScissorRect scissor = run.hasScissor ? run.scissor : fullScissor;
            if (scissor.width == 0 || scissor.height == 0) continue;
            [encoder setScissorRect:scissor];
            if (!OrenAVMMetalBindVertexPayload(encoder, self.device, &transientVertexBuffers, run.vertices, run.vertexBytes)) continue;
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                         vertexStart:0
                         vertexCount:run.vertexBytes / sizeof(OrenAVMMetalVertex)];
        }
    }
    if (encoder && self.orenTextPipelineState) {
        [encoder setRenderPipelineState:self.orenTextPipelineState];
        for (OrenAVMMetalImageRun* run in imageRuns) {
            if (!run.texture) continue;
            MTLScissorRect scissor = run.hasScissor ? run.scissor : fullScissor;
            if (scissor.width == 0 || scissor.height == 0) continue;
            [encoder setScissorRect:scissor];
            if (!OrenAVMMetalBindVertexPayload(encoder, self.device, &transientVertexBuffers, run->vertices, sizeof(run->vertices))) continue;
            [encoder setFragmentTexture:run.texture atIndex:0];
            float opacity = run.opacity;
            [encoder setFragmentBytes:&opacity length:sizeof(opacity) atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                         vertexStart:0
                         vertexCount:6];
        }
        for (OrenAVMMetalTextRun* run in textRuns) {
            NSUInteger vertexBytes = OrenAVMMetalTextRunVertexBytesLength(run);
            if (!run.texture || vertexBytes == 0) continue;
            MTLScissorRect scissor = run.hasScissor ? run.scissor : fullScissor;
            if (scissor.width == 0 || scissor.height == 0) continue;
            [encoder setScissorRect:scissor];
            if (!OrenAVMMetalBindVertexPayload(encoder, self.device, &transientVertexBuffers, OrenAVMMetalTextRunVertexBytes(run), vertexBytes)) continue;
            [encoder setFragmentTexture:run.texture atIndex:0];
            float opacity = run.opacity;
            [encoder setFragmentBytes:&opacity length:sizeof(opacity) atIndex:0];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                         vertexStart:0
                         vertexCount:OrenAVMMetalTextRunVertexCount(run)];
        }
    }
    [encoder endEncoding];
    if (transientVertexBuffers.count > 0) {
        NSArray<id<MTLBuffer>>* retainedVertexBuffers = transientVertexBuffers;
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> completedBuffer) {
            (void)completedBuffer;
            (void)retainedVertexBuffers.count;
        }];
    }
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
    const void* stored = NULL;
    if (_orenTouchIDs && CFDictionaryGetValueIfPresent(_orenTouchIDs, (__bridge const void*)touch, &stored)) {
        return (uint32_t)(uintptr_t)stored;
    }
    uint32_t pointerID = self.orenNextTouchID == 0 ? 1u : self.orenNextTouchID;
    self.orenNextTouchID = pointerID + 1u;
    if (self.orenNextTouchID == 0) self.orenNextTouchID = 1u;
    if (!_orenTouchIDs) _orenTouchIDs = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    if (_orenTouchIDs) {
        CFDictionarySetValue(_orenTouchIDs, (__bridge const void*)touch, (const void*)(uintptr_t)pointerID);
    }
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
        if (releaseAfterSend && _orenTouchIDs) {
            CFDictionaryRemoveValue(_orenTouchIDs, (__bridge const void*)touch);
        }
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
