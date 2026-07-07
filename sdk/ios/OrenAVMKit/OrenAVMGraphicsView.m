#import "OrenAVMKit.h"
#import "OrenAVMGFXInput.h"
#import "OrenAVMGraphicsResources.h"

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

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

static uint16_t OrenAVMGfxReadU16LE(const uint8_t* p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t OrenAVMGfxReadU32LE(const uint8_t* p) {
    return (uint32_t)p[0] |
        ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) |
        ((uint32_t)p[3] << 24);
}

static uint32_t OrenAVMGfxRGBAValue(const uint8_t* rgba) {
    return (uint32_t)rgba[0] |
        ((uint32_t)rgba[1] << 8) |
        ((uint32_t)rgba[2] << 16) |
        ((uint32_t)rgba[3] << 24);
}

static void OrenAVMGfxSetFillColorValue(CGContextRef ctx, uint32_t rgbaValue) {
    CGContextSetRGBFillColor(ctx,
                             (CGFloat)(rgbaValue & 255u) / 255.0,
                             (CGFloat)((rgbaValue >> 8) & 255u) / 255.0,
                             (CGFloat)((rgbaValue >> 16) & 255u) / 255.0,
                             (CGFloat)((rgbaValue >> 24) & 255u) / 255.0);
}

static void OrenAVMGfxSetFillColorBytes(CGContextRef ctx, const uint8_t* rgba) {
    CGContextSetRGBFillColor(ctx,
                             (CGFloat)rgba[0] / 255.0,
                             (CGFloat)rgba[1] / 255.0,
                             (CGFloat)rgba[2] / 255.0,
                             (CGFloat)rgba[3] / 255.0);
}

static void OrenAVMGfxSetStrokeColorBytes(CGContextRef ctx, const uint8_t* rgba) {
    CGContextSetRGBStrokeColor(ctx,
                               (CGFloat)rgba[0] / 255.0,
                               (CGFloat)rgba[1] / 255.0,
                               (CGFloat)rgba[2] / 255.0,
                               (CGFloat)rgba[3] / 255.0);
}

static BOOL OrenAVMGfxFrameDataIsValid(NSData* frame) {
    if (frame.length < 24) return NO;
    const uint8_t* data = (const uint8_t*)frame.bytes;
    if (memcmp(data, "OGF0", 4) != 0) return NO;
    uint8_t version = data[4];
    if (version != 0 && version != 1) return NO;
    uint16_t headerLen = version == 0 ? 24 : OrenAVMGfxReadU16LE(data + 6);
    if (headerLen < 24 || headerLen > frame.length) return NO;
    return OrenAVMGfxReadU32LE(data + 8) != 0 && OrenAVMGfxReadU32LE(data + 12) != 0;
}

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
    const uint8_t* data = (const uint8_t*)frame.bytes;
    uint8_t version = data[4];
    uint16_t headerLen = version == 0 ? 24 : OrenAVMGfxReadU16LE(data + 6);
    if (headerLen < 24 || headerLen > frame.length) return;
    uint32_t width = OrenAVMGfxReadU32LE(data + 8);
    uint32_t height = OrenAVMGfxReadU32LE(data + 12);
    uint32_t opCount = OrenAVMGfxReadU32LE(data + 20);
    if (width == 0 || height == 0) return;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    size_t off = headerLen;
    size_t len = frame.length;
    uint32_t clipDepth = 0;
    uint32_t stateDepth = 0;
    CGFloat opacity = 1.0;
    CGFloat opacityStack[64];
    uint32_t opacityDepth = 0;
    BOOL depthEnabled = NO;
    int32_t nearZ = 0;
    int32_t farZ = 0;
    BOOL depthEnabledStack[64];
    int32_t nearZStack[64];
    int32_t farZStack[64];
    uint32_t cameraDepth = 0;
    for (uint32_t i = 0; i < opCount && off + 4 <= len; i++) {
        uint8_t opcode = data[off];
        uint16_t payloadLen = OrenAVMGfxReadU16LE(data + off + 2);
        off += 4;
        if (off + (size_t)payloadLen > len) return;
        const uint8_t* payload = data + off;

        if (opcode == 1 && payloadLen == 20) {
            uint32_t x = OrenAVMGfxReadU32LE(payload);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t w = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t h = OrenAVMGfxReadU32LE(payload + 12);
            OrenAVMGfxSetFillColorBytes(ctx, payload + 16);
            CGContextFillRect(ctx, CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h));
        } else if (opcode == 16 && payloadLen == 16) {
            uint32_t x = OrenAVMGfxReadU32LE(payload);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t w = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t h = OrenAVMGfxReadU32LE(payload + 12);
            CGContextSaveGState(ctx);
            CGContextClipToRect(ctx, CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h));
            clipDepth++;
            stateDepth++;
        } else if (opcode == 17 && payloadLen == 0) {
            if (clipDepth > 0) {
                CGContextRestoreGState(ctx);
                clipDepth--;
                if (stateDepth > 0) stateDepth--;
            }
        } else if (opcode == 18 && payloadLen == 8) {
            int32_t dx = (int32_t)OrenAVMGfxReadU32LE(payload);
            int32_t dy = (int32_t)OrenAVMGfxReadU32LE(payload + 4);
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, (CGFloat)dx, (CGFloat)dy);
            stateDepth++;
        } else if (opcode == 19 && payloadLen == 0) {
            if (stateDepth > 0) {
                CGContextRestoreGState(ctx);
                stateDepth--;
            }
        } else if (opcode == 20 && payloadLen == 4) {
            uint32_t alphaMilli = OrenAVMGfxReadU32LE(payload);
            if (opacityDepth < 64) {
                opacityStack[opacityDepth++] = opacity;
                opacity = opacity * ((CGFloat)alphaMilli / 1000.0);
                CGContextSaveGState(ctx);
                CGContextSetAlpha(ctx, opacity);
                stateDepth++;
            }
        } else if (opcode == 21 && payloadLen == 0) {
            if (opacityDepth > 0 && stateDepth > 0) {
                CGContextRestoreGState(ctx);
                opacity = opacityStack[--opacityDepth];
                stateDepth--;
            }
        } else if (opcode == 22 && payloadLen == 8) {
            if (cameraDepth < 64) {
                depthEnabledStack[cameraDepth] = depthEnabled;
                nearZStack[cameraDepth] = nearZ;
                farZStack[cameraDepth] = farZ;
                cameraDepth++;
                depthEnabled = YES;
                nearZ = (int32_t)OrenAVMGfxReadU32LE(payload);
                farZ = (int32_t)OrenAVMGfxReadU32LE(payload + 4);
                stateDepth++;
            }
        } else if (opcode == 23 && payloadLen == 0) {
            if (cameraDepth > 0 && stateDepth > 0) {
                cameraDepth--;
                depthEnabled = depthEnabledStack[cameraDepth];
                nearZ = nearZStack[cameraDepth];
                farZ = farZStack[cameraDepth];
                stateDepth--;
            }
        } else if (opcode == 3 && payloadLen == 24) {
            uint32_t x1 = OrenAVMGfxReadU32LE(payload);
            uint32_t y1 = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t x2 = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t y2 = OrenAVMGfxReadU32LE(payload + 12);
            uint32_t width = OrenAVMGfxReadU32LE(payload + 16);
            OrenAVMGfxSetStrokeColorBytes(ctx, payload + 20);
            CGContextSetLineWidth(ctx, (CGFloat)(width == 0 ? 1 : width));
            CGContextMoveToPoint(ctx, (CGFloat)x1, (CGFloat)y1);
            CGContextAddLineToPoint(ctx, (CGFloat)x2, (CGFloat)y2);
            CGContextStrokePath(ctx);
        } else if (opcode == 6 && payloadLen == 24) {
            uint32_t x = OrenAVMGfxReadU32LE(payload);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t w = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t h = OrenAVMGfxReadU32LE(payload + 12);
            uint32_t width = OrenAVMGfxReadU32LE(payload + 16);
            OrenAVMGfxSetStrokeColorBytes(ctx, payload + 20);
            CGContextStrokeRectWithWidth(ctx,
                                         CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h),
                                         (CGFloat)(width == 0 ? 1 : width));
        } else if (opcode == 9 && payloadLen == 32) {
            uint32_t x = OrenAVMGfxReadU32LE(payload);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t w = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t h = OrenAVMGfxReadU32LE(payload + 12);
            uint32_t radius = OrenAVMGfxReadU32LE(payload + 16);
            uint32_t width = OrenAVMGfxReadU32LE(payload + 20);
            uint32_t flags = OrenAVMGfxReadU32LE(payload + 24);
            UIBezierPath* path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h)
                                                             cornerRadius:(CGFloat)radius];
            if ((flags & 1u) != 0) {
                OrenAVMGfxSetFillColorBytes(ctx, payload + 28);
                [path fill];
            } else {
                OrenAVMGfxSetStrokeColorBytes(ctx, payload + 28);
                path.lineWidth = (CGFloat)(width == 0 ? 1 : width);
                [path stroke];
            }
        } else if (opcode == 4 && payloadLen == 20) {
            uint32_t cx = OrenAVMGfxReadU32LE(payload);
            uint32_t cy = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t radius = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t flags = OrenAVMGfxReadU32LE(payload + 12);
            int32_t ox = (int32_t)cx - (int32_t)radius;
            int32_t oy = (int32_t)cy - (int32_t)radius;
            CGRect oval = CGRectMake((CGFloat)ox,
                                     (CGFloat)oy,
                                     (CGFloat)(radius * 2u),
                                     (CGFloat)(radius * 2u));
            if ((flags & 1u) != 0) {
                OrenAVMGfxSetFillColorBytes(ctx, payload + 16);
                CGContextFillEllipseInRect(ctx, oval);
            } else {
                OrenAVMGfxSetStrokeColorBytes(ctx, payload + 16);
                CGContextStrokeEllipseInRect(ctx, oval);
            }
        } else if (opcode == 7 && payloadLen == 28) {
            uint32_t x = OrenAVMGfxReadU32LE(payload);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t w = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t h = OrenAVMGfxReadU32LE(payload + 12);
            uint32_t width = OrenAVMGfxReadU32LE(payload + 16);
            uint32_t flags = OrenAVMGfxReadU32LE(payload + 20);
            CGRect oval = CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h);
            if ((flags & 1u) != 0) {
                OrenAVMGfxSetFillColorBytes(ctx, payload + 24);
                CGContextFillEllipseInRect(ctx, oval);
            } else {
                OrenAVMGfxSetStrokeColorBytes(ctx, payload + 24);
                CGContextSetLineWidth(ctx, (CGFloat)(width == 0 ? 1 : width));
                CGContextStrokeEllipseInRect(ctx, oval);
            }
        } else if (opcode == 8 && payloadLen >= 28 && ((payloadLen - 12) % 8) == 0) {
            uint32_t width = OrenAVMGfxReadU32LE(payload);
            uint32_t pointCount = OrenAVMGfxReadU32LE(payload + 4);
            if (pointCount == ((uint32_t)payloadLen - 12u) / 8u && pointCount >= 2) {
                OrenAVMGfxSetStrokeColorBytes(ctx, payload + 8);
                CGContextSetLineWidth(ctx, (CGFloat)(width == 0 ? 1 : width));
                const uint8_t* points = payload + 12;
                CGContextBeginPath(ctx);
                CGContextMoveToPoint(ctx, (CGFloat)OrenAVMGfxReadU32LE(points), (CGFloat)OrenAVMGfxReadU32LE(points + 4));
                for (uint32_t pi = 1; pi < pointCount; pi++) {
                    const uint8_t* point = points + ((size_t)pi * 8u);
                    CGContextAddLineToPoint(ctx, (CGFloat)OrenAVMGfxReadU32LE(point), (CGFloat)OrenAVMGfxReadU32LE(point + 4));
                }
                CGContextStrokePath(ctx);
            }
        } else if (opcode == 5 && payloadLen == 28) {
            uint32_t x1 = OrenAVMGfxReadU32LE(payload);
            uint32_t y1 = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t x2 = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t y2 = OrenAVMGfxReadU32LE(payload + 12);
            uint32_t x3 = OrenAVMGfxReadU32LE(payload + 16);
            uint32_t y3 = OrenAVMGfxReadU32LE(payload + 20);
            OrenAVMGfxSetFillColorBytes(ctx, payload + 24);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, (CGFloat)x1, (CGFloat)y1);
            CGContextAddLineToPoint(ctx, (CGFloat)x2, (CGFloat)y2);
            CGContextAddLineToPoint(ctx, (CGFloat)x3, (CGFloat)y3);
            CGContextClosePath(ctx);
            CGContextFillPath(ctx);
        } else if (opcode == 10 && payloadLen >= 32 && ((payloadLen - 8) % 24) == 0) {
            uint32_t triangleCount = OrenAVMGfxReadU32LE(payload);
            const uint8_t* tris = payload + 8;
            if (triangleCount == ((uint32_t)payloadLen - 8u) / 24u) {
                OrenAVMGfxSetFillColorBytes(ctx, payload + 4);
                for (uint32_t ti = 0; ti < triangleCount; ti++) {
                    const uint8_t* tri = tris + ((size_t)ti * 24u);
                    CGContextBeginPath(ctx);
                    CGContextMoveToPoint(ctx, (CGFloat)OrenAVMGfxReadU32LE(tri), (CGFloat)OrenAVMGfxReadU32LE(tri + 4));
                    CGContextAddLineToPoint(ctx, (CGFloat)OrenAVMGfxReadU32LE(tri + 8), (CGFloat)OrenAVMGfxReadU32LE(tri + 12));
                    CGContextAddLineToPoint(ctx, (CGFloat)OrenAVMGfxReadU32LE(tri + 16), (CGFloat)OrenAVMGfxReadU32LE(tri + 20));
                    CGContextClosePath(ctx);
                    CGContextFillPath(ctx);
                }
            }
        } else if (opcode == 80 && payloadLen >= 36 && ((payloadLen - 12) % 24) == 0) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t triangleCount = OrenAVMGfxReadU32LE(payload + 8);
            if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 12u) / 24u) {
                (void)OrenAVMGfxPutTriangleMeshResource(&_orenMeshesByID,
                                                        meshID,
                                                        OrenAVMGfxRGBAValue(payload + 4),
                                                        payload + 12,
                                                        (NSUInteger)payloadLen - 12u,
                                                        triangleCount,
                                                        24u,
                                                        NO);
            }
        } else if (opcode == 81 && payloadLen == 4) {
            OrenAVMGfxDrawMesh2DResource(ctx, _orenMeshesByID, OrenAVMGfxReadU32LE(payload));
        } else if (opcode == 82 && payloadLen == 4) {
            OrenAVMGfxRemoveMeshResource(_orenMeshesByID, OrenAVMGfxReadU32LE(payload));
        } else if (opcode == 83 && payloadLen >= 48 && ((payloadLen - 12) % 36) == 0) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t triangleCount = OrenAVMGfxReadU32LE(payload + 8);
            if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 12u) / 36u) {
                (void)OrenAVMGfxPutTriangleMeshResource(&_orenMeshesByID,
                                                        meshID,
                                                        OrenAVMGfxRGBAValue(payload + 4),
                                                        payload + 12,
                                                        (NSUInteger)payloadLen - 12u,
                                                        triangleCount,
                                                        36u,
                                                        NO);
            }
        } else if ((opcode == 84 && payloadLen == 4) || (opcode == 87 && payloadLen == 20) ||
                   (opcode == 90 && payloadLen == 8) || (opcode == 91 && payloadLen == 24) ||
                   (opcode == 94 && payloadLen == 4)) {
            OrenAVMGfxDrawMesh3DResource(ctx,
                                         _orenMeshesByID,
                                         _orenMaterials3DByID,
                                         _orenModels3DByID,
                                         opcode,
                                         payload,
                                         depthEnabled,
                                         nearZ,
                                         farZ);
        } else if (opcode == 85 && payloadLen == 4) {
            OrenAVMGfxRemoveMeshResource(_orenMeshesByID, OrenAVMGfxReadU32LE(payload));
        } else if (opcode == 89 && payloadLen == 8) {
            uint32_t materialID = OrenAVMGfxReadU32LE(payload);
            (void)OrenAVMGfxPutMaterialResource(&_orenMaterials3DByID, materialID, OrenAVMGfxRGBAValue(payload + 4));
        } else if (opcode == 92 && payloadLen == 4) {
            OrenAVMGfxRemoveMaterialResource(_orenMaterials3DByID, OrenAVMGfxReadU32LE(payload));
        } else if (opcode == 93 && payloadLen == 28) {
            uint32_t modelID = OrenAVMGfxReadU32LE(payload);
            uint32_t meshID = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t scaleMilli = OrenAVMGfxReadU32LE(payload + 24);
            (void)OrenAVMGfxPutModelResource(&_orenModels3DByID,
                                             modelID,
                                             meshID,
                                             OrenAVMGfxReadU32LE(payload + 8),
                                             (int32_t)OrenAVMGfxReadU32LE(payload + 12),
                                             (int32_t)OrenAVMGfxReadU32LE(payload + 16),
                                             (int32_t)OrenAVMGfxReadU32LE(payload + 20),
                                             scaleMilli);
        } else if (opcode == 95 && payloadLen == 4) {
            OrenAVMGfxRemoveModelResource(_orenModels3DByID, OrenAVMGfxReadU32LE(payload));
        } else if (opcode == 86 && payloadLen >= 48 && ((payloadLen - 8) % 40) == 0) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t triangleCount = OrenAVMGfxReadU32LE(payload + 4);
            if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 8u) / 40u) {
                (void)OrenAVMGfxPutTriangleMeshResource(&_orenMeshesByID,
                                                        meshID,
                                                        0,
                                                        payload + 8,
                                                        (NSUInteger)payloadLen - 8u,
                                                        triangleCount,
                                                        40u,
                                                        YES);
            }
        } else if (opcode == 88 && payloadLen >= 64) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t vertexCount = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t indexCount = OrenAVMGfxReadU32LE(payload + 12);
            size_t vertexBytes = (size_t)vertexCount * 12u;
            size_t indexBytes = (size_t)indexCount * 4u;
            if (16u + vertexBytes + indexBytes == (size_t)payloadLen) {
                (void)OrenAVMGfxPutIndexedMeshResource(&_orenMeshesByID,
                                                       meshID,
                                                       OrenAVMGfxRGBAValue(payload + 4),
                                                       payload + 16,
                                                       vertexBytes,
                                                       vertexCount,
                                                       payload + 16 + vertexBytes,
                                                       indexBytes,
                                                       indexCount);
            }
        } else if (opcode == 2 && payloadLen >= 16) {
            uint32_t x = OrenAVMGfxReadU32LE(payload);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t textLen = OrenAVMGfxReadU32LE(payload + 12);
            if (textLen <= (uint32_t)payloadLen - 16u) {
                NSDictionary<NSAttributedStringKey, id>* attrs = OrenAVMGfxTextAttributesForRGBA(&_orenTextAttributes,
                                                                                                  &_orenLastTextAttributesRGBA,
                                                                                                  &_orenLastTextAttributes,
                                                                                                  OrenAVMGfxRGBAValue(payload + 8));
                OrenAVMGfxDrawTextBytes(payload + 16, textLen, x, y, attrs);
            }
        } else if (opcode == 68 && payloadLen >= 12) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            uint32_t textLen = OrenAVMGfxReadU32LE(payload + 8);
            if (textLen == (uint32_t)payloadLen - 12u) {
                NSDictionary<NSAttributedStringKey, id>* attrs = OrenAVMGfxTextAttributesForRGBA(&_orenTextAttributes,
                                                                                                  &_orenLastTextAttributesRGBA,
                                                                                                  &_orenLastTextAttributes,
                                                                                                  OrenAVMGfxRGBAValue(payload + 4));
                (void)OrenAVMGfxPutTextResource(&_orenTextResourcesByID, textID, payload + 12, textLen, attrs);
            }
        } else if (opcode == 69 && payloadLen == 12) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            uint32_t x = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 8);
            OrenAVMGfxDrawTextResource(_orenTextResourcesByID, textID, x, y);
        } else if (opcode == 72 && payloadLen >= 16 && ((payloadLen - 8) % 8) == 0) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            uint32_t posCount = OrenAVMGfxReadU32LE(payload + 4);
            if (posCount == ((uint32_t)payloadLen - 8u) / 8u) OrenAVMGfxDrawTextResourcePositions(_orenTextResourcesByID, textID, payload + 8, posCount);
        } else if (opcode == 70 && payloadLen == 4) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            OrenAVMGfxRemoveTextResource(_orenTextResourcesByID, textID);
        } else if (opcode == 64 && payloadLen >= 16) {
            uint32_t imageID = OrenAVMGfxReadU32LE(payload);
            uint32_t iw = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t ih = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t imageLen = OrenAVMGfxReadU32LE(payload + 12);
            if (imageLen == (uint32_t)payloadLen - 16u) {
                UIImage* image = OrenAVMGfxImageRGBA(payload + 16, iw, ih, imageLen);
                (void)OrenAVMGfxPutImageResource(&_orenImagesByID,
                                                 image,
                                                 imageID,
                                                 (NSUInteger)iw * (NSUInteger)ih,
                                                 self.retainedImageCountLimit,
                                                 self.retainedImagePixelLimit,
                                                 &_retainedImagePixelCount);
            }
        } else if (opcode == 65 && payloadLen == 20) {
            uint32_t imageID = OrenAVMGfxReadU32LE(payload);
            uint32_t x = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t w = OrenAVMGfxReadU32LE(payload + 12);
            uint32_t h = OrenAVMGfxReadU32LE(payload + 16);
            UIImage* image = OrenAVMGfxRetainedImageResource(_orenImagesByID, imageID).image;
            if (image) [image drawInRect:CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h)];
        } else if (opcode == 66 && payloadLen == 4) {
            uint32_t imageID = OrenAVMGfxReadU32LE(payload);
            OrenAVMGfxRemoveImageResource(_orenImagesByID, imageID, &_retainedImagePixelCount);
        } else if (opcode == 67 && payloadLen == 36) {
            uint32_t imageID = OrenAVMGfxReadU32LE(payload);
            uint32_t sx = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t sy = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t sw = OrenAVMGfxReadU32LE(payload + 12);
            uint32_t sh = OrenAVMGfxReadU32LE(payload + 16);
            uint32_t x = OrenAVMGfxReadU32LE(payload + 20);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 24);
            uint32_t w = OrenAVMGfxReadU32LE(payload + 28);
            uint32_t h = OrenAVMGfxReadU32LE(payload + 32);
            UIImage* image = OrenAVMGfxRetainedImageResource(_orenImagesByID, imageID).image;
            CGImageRef cgImage = image.CGImage;
            if (cgImage) {
                OrenAVMGfxDrawImageSubrect(cgImage, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage),
                                           sx, sy, sw, sh, x, y, w, h);
            }
        } else if (opcode == 71 && payloadLen >= 40 && ((payloadLen - 8) % 32) == 0) {
            uint32_t imageID = OrenAVMGfxReadU32LE(payload);
            uint32_t rectCount = OrenAVMGfxReadU32LE(payload + 4);
            UIImage* image = OrenAVMGfxRetainedImageResource(_orenImagesByID, imageID).image;
            CGImageRef cgImage = image.CGImage;
            if (cgImage && rectCount == ((uint32_t)payloadLen - 8u) / 32u) {
                size_t imageWidth = CGImageGetWidth(cgImage);
                size_t imageHeight = CGImageGetHeight(cgImage);
                for (uint32_t ri = 0; ri < rectCount; ri++) {
                    const uint8_t* r = payload + 8 + ((size_t)ri * 32u);
                    uint32_t sx = OrenAVMGfxReadU32LE(r);
                    uint32_t sy = OrenAVMGfxReadU32LE(r + 4);
                    uint32_t sw = OrenAVMGfxReadU32LE(r + 8);
                    uint32_t sh = OrenAVMGfxReadU32LE(r + 12);
                    uint32_t x = OrenAVMGfxReadU32LE(r + 16);
                    uint32_t y = OrenAVMGfxReadU32LE(r + 20);
                    uint32_t w = OrenAVMGfxReadU32LE(r + 24);
                    uint32_t h = OrenAVMGfxReadU32LE(r + 28);
                    OrenAVMGfxDrawImageSubrect(cgImage, imageWidth, imageHeight, sx, sy, sw, sh, x, y, w, h);
                }
            }
        }

        off += payloadLen;
    }
    while (stateDepth > 0) {
        CGContextRestoreGState(ctx);
        stateDepth--;
    }
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
