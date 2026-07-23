#import "OrenAVMKit.h"
#import "OrenAVMGFXInput.h"
#import "OrenAVMMetalFrame.h"
#import "OrenAVMMetalGeometry.h"
#import "OrenAVMMetalPipeline.h"
#import "OrenAVMMetalResources.h"
#import "OrenAVMMetalText.h"

#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <Metal/Metal.h>
#import <dispatch/dispatch.h>
#include <math.h>
#include <string.h>

_Static_assert(sizeof(OrenAVMMetalTextVertex) == 16, "OrenAVMMetalTextVertex must match shader packed_float2+packed_float2");

static const NSUInteger OrenAVMMetalDefaultRetainedImagePixelLimit = 16u * 1024u * 1024u;
static const NSUInteger OrenAVMMetalDefaultRetainedImageCountLimit = 1024u;

static BOOL OrenAVMMetalAssignError(NSError** error, NSInteger code, NSString* message) {
    if (error) {
        *error = [NSError errorWithDomain:OrenAVMKitErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message ?: @"OrenAVMMetalView error"}];
    }
    return NO;
}

@interface OrenAVMMetalView () <MTKViewDelegate> {
    CFMutableDictionaryRef _orenTouchIDs;
    CFMutableDictionaryRef _orenTextResourcesByID;
    CFMutableDictionaryRef _orenMeshesByID;
    CFMutableDictionaryRef _orenMeshes3DByID;
    CFMutableDictionaryRef _orenMaterials3DByID;
    CFMutableDictionaryRef _orenModels3DByID;
    CFMutableDictionaryRef _orenImagesByID;
}
@property(nonatomic, strong, nullable) id<MTLCommandQueue> orenCommandQueue;
@property(nonatomic, strong, nullable) id<MTLRenderPipelineState> orenPipelineState;
@property(nonatomic, strong, nullable) id<MTLRenderPipelineState> orenTextPipelineState;
@property(nonatomic, strong) NSMutableDictionary<OrenAVMMetalTextCacheKey*, OrenAVMMetalTextCacheEntry*>* orenTextCache;
@property(nonatomic, strong) NSMutableArray<OrenAVMMetalTextCacheKey*>* orenTextCacheOrder;
@property(nonatomic, strong) OrenAVMMetalTextAttributeCache* orenTextAttributes;
@property(nonatomic) NSUInteger orenTextCachePixels;
@property(nonatomic, strong, nullable) OrenAVMMetalTextAtlas* orenTextAtlas;
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
    if (_orenTextResourcesByID) {
        CFRelease(_orenTextResourcesByID);
        _orenTextResourcesByID = NULL;
    }
    if (_orenMeshesByID) {
        CFRelease(_orenMeshesByID);
        _orenMeshesByID = NULL;
    }
    if (_orenMeshes3DByID) {
        CFRelease(_orenMeshes3DByID);
        _orenMeshes3DByID = NULL;
    }
    if (_orenMaterials3DByID) {
        CFRelease(_orenMaterials3DByID);
        _orenMaterials3DByID = NULL;
    }
    if (_orenModels3DByID) {
        CFRelease(_orenModels3DByID);
        _orenModels3DByID = NULL;
    }
    if (_orenImagesByID) {
        CFRelease(_orenImagesByID);
        _orenImagesByID = NULL;
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
    if (!_orenTextResourcesByID) _orenTextResourcesByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!_orenMeshesByID) _orenMeshesByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!_orenMeshes3DByID) _orenMeshes3DByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!_orenMaterials3DByID) _orenMaterials3DByID = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    if (!_orenModels3DByID) _orenModels3DByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!_orenImagesByID) _orenImagesByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
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
        id<MTLRenderPipelineState> geometryPipeline = nil;
        id<MTLRenderPipelineState> textPipeline = nil;
        (void)OrenAVMMetalBuildPipelineStates(self.device,
                                              self.colorPixelFormat,
                                              &geometryPipeline,
                                              &textPipeline);
        self.orenPipelineState = geometryPipeline;
        self.orenTextPipelineState = textPipeline;
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
    if (_orenImagesByID) CFDictionaryRemoveAllValues(_orenImagesByID);
    self.retainedImagePixelCount = 0;
}

- (NSUInteger)retainedImageCount {
    return _orenImagesByID ? (NSUInteger)CFDictionaryGetCount(_orenImagesByID) : 0;
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
    return OrenAVMGFXInputSendPointerEvent(self.runtime,
                                           kind,
                                           point,
                                           pointerId,
                                           @"metal view has no AVM runtime",
                                           error);
}

- (BOOL)sendPointerEventsWithKind:(uint8_t)kind points:(NSArray<NSValue*>*)points pointerIDs:(NSArray<NSNumber*>*)pointerIDs error:(NSError**)error {
    return OrenAVMGFXInputSendPointerEvents(self.runtime,
                                           kind,
                                           points,
                                           pointerIDs,
                                           @"metal view has no AVM runtime",
                                           @"metal view pointer batch point/id count mismatch",
                                           error);
}

- (BOOL)sendTextInputString:(NSString*)text error:(NSError**)error {
    if (!self.runtime) {
        return OrenAVMMetalAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                       @"metal view has no AVM runtime");
    }
    return [self.runtime putGraphicsTextInputString:text error:error];
}

- (BOOL)sendCompositionEventWithKind:(uint8_t)kind
                                text:(NSString*)text
                      selectionStart:(uint32_t)selectionStart
                        selectionEnd:(uint32_t)selectionEnd
                               error:(NSError**)error {
    if (!self.runtime) {
        return OrenAVMMetalAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                       @"metal view has no AVM runtime");
    }
    return [self.runtime putGraphicsCompositionEventWithKind:kind
                                                        text:text
                                              selectionStart:selectionStart
                                                selectionEnd:selectionEnd
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

- (NSArray<OrenAVMMetalVertexRun*>*)orenVertexRunsForFrame:(NSData*)frame
                                                 clearColor:(MTLClearColor*)clearColor
                                                  textRuns:(NSMutableArray<OrenAVMMetalTextRun*>**)textRuns
                                                 imageRuns:(NSMutableArray<OrenAVMMetalImageRun*>**)imageRuns
                                               runCapacity:(NSUInteger)runCapacity {
    OrenAVMMetalFrameBuildContext context = {
        .device = self.device,
        .screen = self.window.screen,
        .textResources = &_orenTextResourcesByID,
        .meshes2D = &_orenMeshesByID,
        .meshes3D = &_orenMeshes3DByID,
        .materials3D = &_orenMaterials3DByID,
        .models3D = &_orenModels3DByID,
        .images = &_orenImagesByID,
        .textCache = self.orenTextCache,
        .textCacheOrder = self.orenTextCacheOrder,
        .textAttributes = self.orenTextAttributes,
        .textCachePixels = self.orenTextCachePixels,
        .textAtlas = self.orenTextAtlas,
        .retainedImageCountLimit = self.retainedImageCountLimit,
        .retainedImagePixelLimit = self.retainedImagePixelLimit,
        .retainedImagePixelCount = &_retainedImagePixelCount,
    };
    NSArray<OrenAVMMetalVertexRun*>* vertexRuns = OrenAVMMetalBuildVertexRunsForFrame(frame,
                                                                                     clearColor,
                                                                                     textRuns,
                                                                                     imageRuns,
                                                                                     runCapacity,
                                                                                     &context);
    self.orenTextCachePixels = context.textCachePixels;
    self.orenTextAtlas = context.textAtlas;
    return vertexRuns;
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
    NSArray<OrenAVMMetalImageRun*>* coalescedImageRuns = imageRuns ? OrenAVMMetalCoalesceImageRuns(imageRuns) : @[];
    NSArray<OrenAVMMetalTextRun*>* coalescedTextRuns = textRuns ? OrenAVMMetalCoalesceTextRuns(textRuns) : @[];
    uint32_t vertexCount = 0;
    for (OrenAVMMetalVertexRun* run in vertexRuns) {
        vertexCount += (uint32_t)(run.vertexBytes / sizeof(OrenAVMMetalVertex));
    }
    self.lastFrameVertexCount = vertexCount;
    self.lastFrameTextRunCount = (uint32_t)coalescedTextRuns.count;
    self.lastFrameImageRunCount = (uint32_t)coalescedImageRuns.count;
    if (clearColorOut) *clearColorOut = clearColor;
    if (imageRunsOut) *imageRunsOut = coalescedImageRuns;
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
    OrenAVMMetalEncodePreparedRuns(encoder,
                                   self.device,
                                   self.orenPipelineState,
                                   self.orenTextPipelineState,
                                   drawable.texture,
                                   vertexRuns,
                                   imageRuns,
                                   textRuns,
                                   &transientVertexBuffers);
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

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    OrenAVMGFXInputSendTouches(self.runtime, self, &_orenTouchIDs, &_orenNextTouchID,
                               touches, 1, NO, @"metal view has no AVM runtime");
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    OrenAVMGFXInputSendTouches(self.runtime, self, &_orenTouchIDs, &_orenNextTouchID,
                               touches, 2, NO, @"metal view has no AVM runtime");
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    OrenAVMGFXInputSendTouches(self.runtime, self, &_orenTouchIDs, &_orenNextTouchID,
                               touches, 3, YES, @"metal view has no AVM runtime");
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    OrenAVMGFXInputSendTouches(self.runtime, self, &_orenTouchIDs, &_orenNextTouchID,
                               touches, 4, YES, @"metal view has no AVM runtime");
}

@end

#endif
