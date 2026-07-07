#import "OrenAVMKit.h"
#import "OrenAVMGFXInput.h"
#import "OrenAVMGraphicsFrame.h"

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#include <math.h>
#include <stdlib.h>

static BOOL OrenAVMGraphicsViewAssignError(NSError** error, NSInteger code, NSString* message) {
    if (error) {
        *error = [NSError errorWithDomain:OrenAVMKitErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: message ?: @"OrenAVMGraphicsView error"}];
    }
    return NO;
}

static const NSUInteger OrenAVMDefaultRetainedImagePixelLimit = 16u * 1024u * 1024u;
static const NSUInteger OrenAVMDefaultRetainedImageCountLimit = 1024u;

@interface OrenAVMGraphicsView () {
    CFMutableDictionaryRef _orenTouchIDs;
    CFMutableDictionaryRef _orenTextAttributes;
    CFMutableDictionaryRef _orenTextResourcesByID;
    CFMutableDictionaryRef _orenMeshesByID;
    CFMutableDictionaryRef _orenMaterials3DByID;
    CFMutableDictionaryRef _orenModels3DByID;
    CFMutableDictionaryRef _orenImagesByID;
    uint32_t _orenLastTextAttributesRGBA;
    NSDictionary<NSAttributedStringKey, id>* _orenLastTextAttributes;
}
@property(nonatomic) uint32_t orenNextTouchID;
@property(nonatomic, readwrite) NSUInteger retainedImagePixelCount;
@property(nonatomic, strong) id orenGraphicsFrameObserverToken;
@property(nonatomic) BOOL orenFrameReloadScheduled;
@end

@implementation OrenAVMGraphicsView

- (void)orenConfigureGraphicsView {
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.multipleTouchEnabled = YES;
    if (!_orenTouchIDs) _orenTouchIDs = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    if (self.orenNextTouchID == 0) self.orenNextTouchID = 1u;
    if (!_orenTextResourcesByID) _orenTextResourcesByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!_orenTextAttributes) _orenTextAttributes = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!_orenMeshesByID) _orenMeshesByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!_orenMaterials3DByID) _orenMaterials3DByID = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    if (!_orenModels3DByID) _orenModels3DByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!_orenImagesByID) _orenImagesByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (self.retainedImagePixelLimit == 0) self.retainedImagePixelLimit = OrenAVMDefaultRetainedImagePixelLimit;
    if (self.retainedImageCountLimit == 0) self.retainedImageCountLimit = OrenAVMDefaultRetainedImageCountLimit;
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
    if (_orenTextAttributes) {
        CFRelease(_orenTextAttributes);
        _orenTextAttributes = NULL;
    }
    if (_orenTextResourcesByID) {
        CFRelease(_orenTextResourcesByID);
        _orenTextResourcesByID = NULL;
    }
    if (_orenMeshesByID) {
        CFRelease(_orenMeshesByID);
        _orenMeshesByID = NULL;
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

- (NSUInteger)retainedImageCount {
    return _orenImagesByID ? (NSUInteger)CFDictionaryGetCount(_orenImagesByID) : 0;
}

- (BOOL)hasValidFrameData {
    return OrenAVMGfxFrameDataIsValid(self.frameData);
}

- (void)clearImageCache {
    if (_orenImagesByID) CFDictionaryRemoveAllValues(_orenImagesByID);
    self.retainedImagePixelCount = 0;
}

- (instancetype)initWithRuntime:(OrenAVMRuntime*)runtime {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    [self orenConfigureGraphicsView];
    self.runtime = runtime;
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    [self orenConfigureGraphicsView];
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    self = [super initWithCoder:coder];
    if (!self) return nil;
    [self orenConfigureGraphicsView];
    return self;
}

- (BOOL)reloadFrameWithError:(NSError**)error {
    if (!self.runtime) {
        return OrenAVMGraphicsViewAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"graphics view has no AVM runtime");
    }
    if (![self.runtime hasGraphicsFrameWithError:error]) return YES;
    NSData* frame = [self.runtime getGraphicsFrameDataWithError:error];
    if (!frame) return NO;
    if (!OrenAVMGfxFrameDataIsValid(frame)) return YES;
    self.frameData = frame;
    [self setNeedsDisplay];
    return YES;
}

- (BOOL)sendPointerEventWithKind:(uint8_t)kind point:(CGPoint)point pointerId:(uint32_t)pointerId error:(NSError**)error {
    return OrenAVMGFXInputSendPointerEvent(self.runtime,
                                           kind,
                                           point,
                                           pointerId,
                                           @"graphics view has no AVM runtime",
                                           error);
}

- (BOOL)sendPointerEventsWithKind:(uint8_t)kind points:(NSArray<NSValue*>*)points pointerIDs:(NSArray<NSNumber*>*)pointerIDs error:(NSError**)error {
    return OrenAVMGFXInputSendPointerEvents(self.runtime,
                                           kind,
                                           points,
                                           pointerIDs,
                                           @"graphics view has no AVM runtime",
                                           @"graphics pointer batch point/id count mismatch",
                                           error);
}

- (BOOL)sendResizeEventWithScaleMilli:(uint32_t)scaleMilli error:(NSError**)error {
    if (!self.runtime) {
        return OrenAVMGraphicsViewAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"graphics view has no AVM runtime");
    }
    CGSize size = self.bounds.size;
    return [self.runtime putGraphicsResizeEventWithWidth:(uint32_t)llround((double)size.width)
                                                  height:(uint32_t)llround((double)size.height)
                                              scaleMilli:scaleMilli
                                                  error:error];
}

- (BOOL)sendTextInputString:(NSString*)text error:(NSError**)error {
    if (!self.runtime) {
        return OrenAVMGraphicsViewAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"graphics view has no AVM runtime");
    }
    return [self.runtime putGraphicsTextInputString:text error:error];
}

- (BOOL)sendCompositionEventWithKind:(uint8_t)kind
                                text:(NSString*)text
                      selectionStart:(uint32_t)selectionStart
                        selectionEnd:(uint32_t)selectionEnd
                               error:(NSError**)error {
    if (!self.runtime) {
        return OrenAVMGraphicsViewAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"graphics view has no AVM runtime");
    }
    return [self.runtime putGraphicsCompositionEventWithKind:kind
                                                        text:text
                                              selectionStart:selectionStart
                                                selectionEnd:selectionEnd
                                                       error:error];
}

- (BOOL)sendMediaEventWithTargetHzMilli:(uint32_t)targetHzMilli flags:(uint32_t)flags error:(NSError**)error {
    if (![self publishScreenStateWithTargetHzMilli:targetHzMilli flags:flags error:error]) return NO;
    CGSize size = self.bounds.size;
    CGFloat scale = self.window.screen.scale;
    if (scale <= 0.0) scale = UIScreen.mainScreen.scale;
    uint32_t scaleMilli = (uint32_t)llround((double)scale * 1000.0);
    uint32_t width = (uint32_t)llround((double)size.width);
    uint32_t height = (uint32_t)llround((double)size.height);
    uint32_t drawableWidth = (uint32_t)llround((double)size.width * (double)scale);
    uint32_t drawableHeight = (uint32_t)llround((double)size.height * (double)scale);
    uint32_t hz = targetHzMilli;
    if (hz == 0) hz = (uint32_t)UIScreen.mainScreen.maximumFramesPerSecond * 1000u;
    return [self.runtime putGraphicsMediaEventWithWidth:width
                                                 height:height
                                             scaleMilli:scaleMilli
                                          drawableWidth:drawableWidth
                                         drawableHeight:drawableHeight
                                          targetHzMilli:hz
                                                  flags:flags
                                                  error:error];
}

- (BOOL)publishScreenStateWithTargetHzMilli:(uint32_t)targetHzMilli flags:(uint32_t)flags error:(NSError**)error {
    if (!self.runtime) {
        return OrenAVMGraphicsViewAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"graphics view has no AVM runtime");
    }
    CGSize size = self.bounds.size;
    CGFloat scale = self.window.screen.scale;
    if (scale <= 0.0) scale = UIScreen.mainScreen.scale;
    uint32_t scaleMilli = (uint32_t)llround((double)scale * 1000.0);
    uint32_t width = (uint32_t)llround((double)size.width);
    uint32_t height = (uint32_t)llround((double)size.height);
    uint32_t drawableWidth = (uint32_t)llround((double)size.width * (double)scale);
    uint32_t drawableHeight = (uint32_t)llround((double)size.height * (double)scale);
    uint32_t hz = targetHzMilli;
    if (hz == 0) hz = (uint32_t)UIScreen.mainScreen.maximumFramesPerSecond * 1000u;
    return [self.runtime setGraphicsScreenWithID:0
                                           width:width
                                          height:height
                                      scaleMilli:scaleMilli
                                   drawableWidth:drawableWidth
                                  drawableHeight:drawableHeight
                                   targetHzMilli:hz
                                           flags:flags
                                           error:error];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.runtime) {
        (void)[self publishScreenStateWithTargetHzMilli:0 flags:0 error:nil];
    }
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    NSData* frame = self.frameData;
    if (!OrenAVMGfxFrameDataIsValid(frame)) return;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    OrenAVMGfxFrameDrawContext context = {
        .textAttributes = &_orenTextAttributes,
        .lastTextAttributesRGBA = &_orenLastTextAttributesRGBA,
        .lastTextAttributes = &_orenLastTextAttributes,
        .textResources = &_orenTextResourcesByID,
        .meshes = &_orenMeshesByID,
        .materials3D = &_orenMaterials3DByID,
        .models3D = &_orenModels3DByID,
        .images = &_orenImagesByID,
        .retainedImageCountLimit = self.retainedImageCountLimit,
        .retainedImagePixelLimit = self.retainedImagePixelLimit,
        .retainedImagePixelCount = &_retainedImagePixelCount,
    };
    OrenAVMGfxDrawFrame(ctx, frame, &context);
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    OrenAVMGFXInputSendTouches(self.runtime, self, &_orenTouchIDs, &_orenNextTouchID,
                               touches, 1, NO, @"graphics view has no AVM runtime");
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    OrenAVMGFXInputSendTouches(self.runtime, self, &_orenTouchIDs, &_orenNextTouchID,
                               touches, 2, NO, @"graphics view has no AVM runtime");
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    OrenAVMGFXInputSendTouches(self.runtime, self, &_orenTouchIDs, &_orenNextTouchID,
                               touches, 3, YES, @"graphics view has no AVM runtime");
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    (void)event;
    OrenAVMGFXInputSendTouches(self.runtime, self, &_orenTouchIDs, &_orenNextTouchID,
                               touches, 4, YES, @"graphics view has no AVM runtime");
}

@end

#endif
