#import "OrenAVMKit.h"

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint32_t triangle;
    int64_t zsum;
} OrenAVMGfxTriangleOrder;

@interface OrenAVMGfxMeshResource : NSObject
@property(nonatomic, strong) NSData* triangles;
@property(nonatomic, strong) NSData* vertices;
@property(nonatomic, strong) NSData* indices;
@property(nonatomic) uint32_t rgbaValue;
@property(nonatomic) uint32_t triangleCount;
@property(nonatomic) uint32_t indexCount;
@property(nonatomic) uint32_t stride;
@property(nonatomic) BOOL hasRGBA;
@end

@implementation OrenAVMGfxMeshResource
@end

@interface OrenAVMGfxTextResource : NSObject
@property(nonatomic, copy) NSString* text;
@property(nonatomic, strong) NSDictionary<NSAttributedStringKey, id>* attributes;
@end

@implementation OrenAVMGfxTextResource
@end

@interface OrenAVMGfxImageResource : NSObject
@property(nonatomic, strong) UIImage* image;
@property(nonatomic) NSUInteger pixels;
@end

@implementation OrenAVMGfxImageResource
@end

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

static int64_t OrenAVMGfxMesh3DZSum(const uint8_t* tri) {
    return (int64_t)(int32_t)OrenAVMGfxReadU32LE(tri + 8) +
        (int64_t)(int32_t)OrenAVMGfxReadU32LE(tri + 20) +
        (int64_t)(int32_t)OrenAVMGfxReadU32LE(tri + 32);
}

static int64_t OrenAVMGfxMesh3DZSumModel(const uint8_t* tri, int32_t offset, uint32_t scaleMilli) {
    return (OrenAVMGfxMesh3DZSum(tri) * (int64_t)scaleMilli) / 1000 + (int64_t)offset * 3;
}

static BOOL OrenAVMGfxMesh3DZVisible(int64_t zsum, BOOL depthEnabled, int32_t nearZ, int32_t farZ) {
    if (!depthEnabled) return YES;
    return zsum >= (int64_t)nearZ * 3 && zsum <= (int64_t)farZ * 3;
}

static int OrenAVMGfxTriangleOrderCompare(const void* left, const void* right) {
    const OrenAVMGfxTriangleOrder* a = (const OrenAVMGfxTriangleOrder*)left;
    const OrenAVMGfxTriangleOrder* b = (const OrenAVMGfxTriangleOrder*)right;
    if (a->zsum > b->zsum) return -1;
    if (a->zsum < b->zsum) return 1;
    if (a->triangle < b->triangle) return -1;
    if (a->triangle > b->triangle) return 1;
    return 0;
}

static OrenAVMGfxTriangleOrder* OrenAVMGfxTriangleOrderBuffer(uint32_t triangleCount, NSMutableData** storage) {
    if (storage) *storage = nil;
    if (triangleCount == 0 || !storage) return NULL;
    NSMutableData* data = [NSMutableData dataWithLength:(NSUInteger)triangleCount * sizeof(OrenAVMGfxTriangleOrder)];
    OrenAVMGfxTriangleOrder* bytes = data.mutableBytes;
    if (!bytes) return NULL;
    *storage = data;
    return bytes;
}

static void OrenAVMGfxSortTriangleOrder(OrenAVMGfxTriangleOrder* order, uint32_t count) {
    if (count > 1) qsort(order, count, sizeof(OrenAVMGfxTriangleOrder), OrenAVMGfxTriangleOrderCompare);
}

static int64_t OrenAVMGfxMesh3DIndexedZSumModel(const uint8_t* vertices,
                                                const uint8_t* indices,
                                                uint32_t triangle,
                                                int32_t offset,
                                                uint32_t scaleMilli) {
    const uint8_t* tri = indices + ((size_t)triangle * 12u);
    uint32_t i1 = OrenAVMGfxReadU32LE(tri);
    uint32_t i2 = OrenAVMGfxReadU32LE(tri + 4);
    uint32_t i3 = OrenAVMGfxReadU32LE(tri + 8);
    int64_t z = (int64_t)(int32_t)OrenAVMGfxReadU32LE(vertices + ((size_t)i1 * 12u) + 8) +
        (int64_t)(int32_t)OrenAVMGfxReadU32LE(vertices + ((size_t)i2 * 12u) + 8) +
        (int64_t)(int32_t)OrenAVMGfxReadU32LE(vertices + ((size_t)i3 * 12u) + 8);
    return (z * (int64_t)scaleMilli) / 1000 + (int64_t)offset * 3;
}

static CGFloat OrenAVMGfxMesh3DModelCoord(const uint8_t* p, int32_t offset, uint32_t scaleMilli) {
    int32_t v = (int32_t)OrenAVMGfxReadU32LE(p);
    return (CGFloat)(((int64_t)v * (int64_t)scaleMilli) / 1000 + (int64_t)offset);
}

static UIColor* OrenAVMGfxColor(const uint8_t* rgba) {
    return [UIColor colorWithRed:(CGFloat)rgba[0] / 255.0
                           green:(CGFloat)rgba[1] / 255.0
                            blue:(CGFloat)rgba[2] / 255.0
                           alpha:(CGFloat)rgba[3] / 255.0];
}

static UIColor* OrenAVMGfxColorValue(uint32_t rgbaValue) {
    return [UIColor colorWithRed:(CGFloat)(rgbaValue & 255u) / 255.0
                           green:(CGFloat)((rgbaValue >> 8) & 255u) / 255.0
                            blue:(CGFloat)((rgbaValue >> 16) & 255u) / 255.0
                           alpha:(CGFloat)((rgbaValue >> 24) & 255u) / 255.0];
}

static UIFont* OrenAVMGfxTextFont(void) {
    static UIFont* font;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        font = [UIFont systemFontOfSize:14.0];
    });
    return font;
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

static NSDictionary<NSAttributedStringKey, id>* OrenAVMGfxTextAttributes(uint32_t rgbaValue) {
    return @{
        NSForegroundColorAttributeName: OrenAVMGfxColorValue(rgbaValue),
        NSFontAttributeName: OrenAVMGfxTextFont()
    };
}

static UIImage* OrenAVMGfxImageRGBA(const uint8_t* rgba, uint32_t width, uint32_t height, uint32_t byteCount) {
    uint64_t expected = (uint64_t)width * (uint64_t)height * 4ull;
    if (!rgba || width == 0 || height == 0 || expected != (uint64_t)byteCount) return nil;
    NSData* imageData = [NSData dataWithBytes:rgba length:(NSUInteger)byteCount];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)imageData);
    if (!provider) return nil;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate((size_t)width,
                                     (size_t)height,
                                     8,
                                     32,
                                     (size_t)width * 4u,
                                     colorSpace,
                                     kCGBitmapByteOrder32Big | kCGImageAlphaLast,
                                     provider,
                                     NULL,
                                     false,
                                     kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    if (!image) return nil;
    UIImage* out = [UIImage imageWithCGImage:image];
    CGImageRelease(image);
    return out;
}

static BOOL OrenAVMGfxSubrectInImage(uint32_t sx, uint32_t sy, uint32_t sw, uint32_t sh, size_t width, size_t height) {
    return (uint64_t)sx + (uint64_t)sw <= (uint64_t)width &&
        (uint64_t)sy + (uint64_t)sh <= (uint64_t)height;
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

@interface OrenAVMGraphicsView ()
@property(nonatomic, strong) NSMapTable<UITouch*, NSNumber*>* orenTouchIDs;
@property(nonatomic) uint32_t orenNextTouchID;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, OrenAVMGfxTextResource*>* orenTextResources;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, OrenAVMGfxMeshResource*>* orenMeshes;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, NSNumber*>* orenMaterials3D;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, NSDictionary<NSString*, NSNumber*>*>* orenModels3D;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, OrenAVMGfxImageResource*>* orenImages;
@property(nonatomic, readwrite) NSUInteger retainedImagePixelCount;
@property(nonatomic, strong) id orenGraphicsFrameObserverToken;
@property(nonatomic) BOOL orenFrameReloadScheduled;
@end

@implementation OrenAVMGraphicsView

- (void)orenConfigureGraphicsView {
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.multipleTouchEnabled = YES;
    if (!self.orenTouchIDs) self.orenTouchIDs = [NSMapTable strongToStrongObjectsMapTable];
    if (self.orenNextTouchID == 0) self.orenNextTouchID = 1u;
    if (!self.orenTextResources) self.orenTextResources = [NSMutableDictionary dictionary];
    if (!self.orenMeshes) self.orenMeshes = [NSMutableDictionary dictionary];
    if (!self.orenMaterials3D) self.orenMaterials3D = [NSMutableDictionary dictionary];
    if (!self.orenModels3D) self.orenModels3D = [NSMutableDictionary dictionary];
    if (!self.orenImages) self.orenImages = [NSMutableDictionary dictionary];
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
}

- (NSUInteger)retainedImageCount {
    return self.orenImages.count;
}

- (BOOL)hasValidFrameData {
    return OrenAVMGfxFrameDataIsValid(self.frameData);
}

- (void)clearImageCache {
    [self.orenImages removeAllObjects];
    self.retainedImagePixelCount = 0;
}

- (void)orenRemoveImageWithID:(uint32_t)imageID {
    NSNumber* key = @(imageID);
    OrenAVMGfxImageResource* old = self.orenImages[key];
    if (old) {
        NSUInteger pixels = old.pixels;
        self.retainedImagePixelCount = self.retainedImagePixelCount > pixels ? self.retainedImagePixelCount - pixels : 0;
    }
    [self.orenImages removeObjectForKey:key];
}

- (void)orenPutImage:(UIImage*)image imageID:(uint32_t)imageID pixels:(NSUInteger)pixels {
    if (!image || imageID == 0) return;
    NSNumber* key = @(imageID);
    OrenAVMGfxImageResource* oldResource = self.orenImages[key];
    NSUInteger oldPixels = oldResource ? oldResource.pixels : 0;
    NSUInteger countAfter = oldResource ? self.orenImages.count : self.orenImages.count + 1u;
    NSUInteger retainedAfterOld = self.retainedImagePixelCount >= oldPixels ? self.retainedImagePixelCount - oldPixels : 0;
    if (pixels > NSUIntegerMax - retainedAfterOld) return;
    NSUInteger pixelAfter = retainedAfterOld + pixels;
    if (self.retainedImageCountLimit == 0 || countAfter > self.retainedImageCountLimit) return;
    if (self.retainedImagePixelLimit == 0 || pixels > self.retainedImagePixelLimit || pixelAfter > self.retainedImagePixelLimit) return;
    OrenAVMGfxImageResource* resource = [[OrenAVMGfxImageResource alloc] init];
    resource.image = image;
    resource.pixels = pixels;
    self.orenImages[key] = resource;
    self.retainedImagePixelCount = pixelAfter;
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
    if (!self.runtime) {
        return OrenAVMGraphicsViewAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"graphics view has no AVM runtime");
    }
    return [self.runtime putGraphicsPointerEventWithKind:kind
                                                       x:(int32_t)llround((double)point.x)
                                                       y:(int32_t)llround((double)point.y)
                                               pointerId:pointerId
                                                   error:error];
}

- (BOOL)sendPointerEventsWithKind:(uint8_t)kind points:(NSArray<NSValue*>*)points pointerIDs:(NSArray<NSNumber*>*)pointerIDs error:(NSError**)error {
    if (points.count != pointerIDs.count) {
        return OrenAVMGraphicsViewAssignError(error, AVM_EMBED_ERR_INVALID_ARG,
                                        @"graphics pointer batch point/id count mismatch");
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
            UIColor* color = OrenAVMGfxColor(payload + 16);
            CGContextSetFillColorWithColor(ctx, color.CGColor);
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
            UIColor* color = OrenAVMGfxColor(payload + 20);
            CGContextSetStrokeColorWithColor(ctx, color.CGColor);
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
            UIColor* color = OrenAVMGfxColor(payload + 20);
            CGContextSetStrokeColorWithColor(ctx, color.CGColor);
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
            UIColor* color = OrenAVMGfxColor(payload + 28);
            UIBezierPath* path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h)
                                                             cornerRadius:(CGFloat)radius];
            if ((flags & 1u) != 0) {
                CGContextSetFillColorWithColor(ctx, color.CGColor);
                [path fill];
            } else {
                CGContextSetStrokeColorWithColor(ctx, color.CGColor);
                path.lineWidth = (CGFloat)(width == 0 ? 1 : width);
                [path stroke];
            }
        } else if (opcode == 4 && payloadLen == 20) {
            uint32_t cx = OrenAVMGfxReadU32LE(payload);
            uint32_t cy = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t radius = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t flags = OrenAVMGfxReadU32LE(payload + 12);
            UIColor* color = OrenAVMGfxColor(payload + 16);
            int32_t ox = (int32_t)cx - (int32_t)radius;
            int32_t oy = (int32_t)cy - (int32_t)radius;
            CGRect oval = CGRectMake((CGFloat)ox,
                                     (CGFloat)oy,
                                     (CGFloat)(radius * 2u),
                                     (CGFloat)(radius * 2u));
            if ((flags & 1u) != 0) {
                CGContextSetFillColorWithColor(ctx, color.CGColor);
                CGContextFillEllipseInRect(ctx, oval);
            } else {
                CGContextSetStrokeColorWithColor(ctx, color.CGColor);
                CGContextStrokeEllipseInRect(ctx, oval);
            }
        } else if (opcode == 7 && payloadLen == 28) {
            uint32_t x = OrenAVMGfxReadU32LE(payload);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t w = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t h = OrenAVMGfxReadU32LE(payload + 12);
            uint32_t width = OrenAVMGfxReadU32LE(payload + 16);
            uint32_t flags = OrenAVMGfxReadU32LE(payload + 20);
            UIColor* color = OrenAVMGfxColor(payload + 24);
            CGRect oval = CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h);
            if ((flags & 1u) != 0) {
                CGContextSetFillColorWithColor(ctx, color.CGColor);
                CGContextFillEllipseInRect(ctx, oval);
            } else {
                CGContextSetStrokeColorWithColor(ctx, color.CGColor);
                CGContextSetLineWidth(ctx, (CGFloat)(width == 0 ? 1 : width));
                CGContextStrokeEllipseInRect(ctx, oval);
            }
        } else if (opcode == 8 && payloadLen >= 28 && ((payloadLen - 12) % 8) == 0) {
            uint32_t width = OrenAVMGfxReadU32LE(payload);
            uint32_t pointCount = OrenAVMGfxReadU32LE(payload + 4);
            if (pointCount == ((uint32_t)payloadLen - 12u) / 8u && pointCount >= 2) {
                UIColor* color = OrenAVMGfxColor(payload + 8);
                CGContextSetStrokeColorWithColor(ctx, color.CGColor);
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
            UIColor* color = OrenAVMGfxColor(payload + 24);
            CGContextSetFillColorWithColor(ctx, color.CGColor);
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, (CGFloat)x1, (CGFloat)y1);
            CGContextAddLineToPoint(ctx, (CGFloat)x2, (CGFloat)y2);
            CGContextAddLineToPoint(ctx, (CGFloat)x3, (CGFloat)y3);
            CGContextClosePath(ctx);
            CGContextFillPath(ctx);
        } else if (opcode == 10 && payloadLen >= 32 && ((payloadLen - 8) % 24) == 0) {
            uint32_t triangleCount = OrenAVMGfxReadU32LE(payload);
            UIColor* color = OrenAVMGfxColor(payload + 4);
            const uint8_t* tris = payload + 8;
            if (triangleCount == ((uint32_t)payloadLen - 8u) / 24u) {
                CGContextSetFillColorWithColor(ctx, color.CGColor);
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
                OrenAVMGfxMeshResource* mesh = [[OrenAVMGfxMeshResource alloc] init];
                mesh.rgbaValue = OrenAVMGfxRGBAValue(payload + 4);
                mesh.triangles = [NSData dataWithBytes:payload + 12 length:(NSUInteger)payloadLen - 12u];
                mesh.triangleCount = triangleCount;
                mesh.stride = 24u;
                self.orenMeshes[@(meshID)] = mesh;
            }
        } else if (opcode == 81 && payloadLen == 4) {
            OrenAVMGfxMeshResource* mesh = self.orenMeshes[@(OrenAVMGfxReadU32LE(payload))];
            NSData* triangles = mesh.triangles;
            const uint8_t* tris = triangles.bytes;
            if (tris && mesh.triangleCount == triangles.length / 24u) {
                OrenAVMGfxSetFillColorValue(ctx, mesh.rgbaValue);
                for (uint32_t ti = 0; ti < mesh.triangleCount; ti++) {
                    const uint8_t* tri = tris + ((size_t)ti * 24u);
                    CGContextBeginPath(ctx);
                    CGContextMoveToPoint(ctx, (CGFloat)OrenAVMGfxReadU32LE(tri), (CGFloat)OrenAVMGfxReadU32LE(tri + 4));
                    CGContextAddLineToPoint(ctx, (CGFloat)OrenAVMGfxReadU32LE(tri + 8), (CGFloat)OrenAVMGfxReadU32LE(tri + 12));
                    CGContextAddLineToPoint(ctx, (CGFloat)OrenAVMGfxReadU32LE(tri + 16), (CGFloat)OrenAVMGfxReadU32LE(tri + 20));
                    CGContextClosePath(ctx);
                    CGContextFillPath(ctx);
                }
            }
        } else if (opcode == 82 && payloadLen == 4) {
            [self.orenMeshes removeObjectForKey:@(OrenAVMGfxReadU32LE(payload))];
        } else if (opcode == 83 && payloadLen >= 48 && ((payloadLen - 12) % 36) == 0) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t triangleCount = OrenAVMGfxReadU32LE(payload + 8);
            if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 12u) / 36u) {
                OrenAVMGfxMeshResource* mesh = [[OrenAVMGfxMeshResource alloc] init];
                mesh.rgbaValue = OrenAVMGfxRGBAValue(payload + 4);
                mesh.triangles = [NSData dataWithBytes:payload + 12 length:(NSUInteger)payloadLen - 12u];
                mesh.triangleCount = triangleCount;
                mesh.stride = 36u;
                self.orenMeshes[@(meshID)] = mesh;
            }
        } else if ((opcode == 84 && payloadLen == 4) || (opcode == 87 && payloadLen == 20) ||
                   (opcode == 90 && payloadLen == 8) || (opcode == 91 && payloadLen == 24) ||
                   (opcode == 94 && payloadLen == 4)) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t materialID = 0;
            int32_t modelX = 0;
            int32_t modelY = 0;
            int32_t modelZ = 0;
            uint32_t scaleMilli = 1000u;
            if (opcode == 94) {
                NSDictionary<NSString*, NSNumber*>* model = self.orenModels3D[@(meshID)];
                if (!model) {
                    off += payloadLen;
                    continue;
                }
                meshID = model[@"mesh_id"].unsignedIntValue;
                materialID = model[@"material_id"].unsignedIntValue;
                modelX = model[@"x"].intValue;
                modelY = model[@"y"].intValue;
                modelZ = model[@"z"].intValue;
                scaleMilli = model[@"scale_milli"].unsignedIntValue;
            }
            OrenAVMGfxMeshResource* mesh = self.orenMeshes[@(meshID)];
            NSNumber* materialRGBAValue = nil;
            if (opcode == 90 || opcode == 91) {
                materialID = OrenAVMGfxReadU32LE(payload + 4);
            }
            if (materialID != 0) {
                materialRGBAValue = self.orenMaterials3D[@(materialID)];
                if (!materialRGBAValue) {
                    off += payloadLen;
                    continue;
                }
            }
            NSData* triangles = mesh.triangles;
            NSData* vertices = mesh.vertices;
            NSData* indices = mesh.indices;
            const uint8_t* tris = triangles.bytes;
            const uint8_t* verts = vertices.bytes;
            const uint8_t* idx = indices.bytes;
            uint32_t meshStride = mesh.stride;
            uint32_t triangleCount = mesh.triangleCount;
            uint32_t rgbaValue = materialRGBAValue ? materialRGBAValue.unsignedIntValue : mesh.rgbaValue;
            if (opcode == 87) {
                modelX = (int32_t)OrenAVMGfxReadU32LE(payload + 4);
                modelY = (int32_t)OrenAVMGfxReadU32LE(payload + 8);
                modelZ = (int32_t)OrenAVMGfxReadU32LE(payload + 12);
                scaleMilli = OrenAVMGfxReadU32LE(payload + 16);
            } else if (opcode == 91) {
                modelX = (int32_t)OrenAVMGfxReadU32LE(payload + 8);
                modelY = (int32_t)OrenAVMGfxReadU32LE(payload + 12);
                modelZ = (int32_t)OrenAVMGfxReadU32LE(payload + 16);
                scaleMilli = OrenAVMGfxReadU32LE(payload + 20);
            }
            if (verts && idx && scaleMilli != 0 && triangleCount == indices.length / 12u && vertices.length % 12u == 0) {
                NSMutableData* orderData = nil;
                OrenAVMGfxTriangleOrder* order = OrenAVMGfxTriangleOrderBuffer(triangleCount, &orderData);
                if (!order) {
                    off += payloadLen;
                    continue;
                }
                uint32_t visibleCount = 0;
                for (uint32_t ti = 0; ti < triangleCount; ti++) {
                    int64_t z = OrenAVMGfxMesh3DIndexedZSumModel(verts, idx, ti, modelZ, scaleMilli);
                    if (!OrenAVMGfxMesh3DZVisible(z, depthEnabled, nearZ, farZ)) continue;
                    order[visibleCount++] = (OrenAVMGfxTriangleOrder){ti, z};
                }
                OrenAVMGfxSortTriangleOrder(order, visibleCount);
                OrenAVMGfxSetFillColorValue(ctx, rgbaValue);
                for (uint32_t oi = 0; oi < visibleCount; oi++) {
                    const uint8_t* tri = idx + ((size_t)order[oi].triangle * 12u);
                    const uint8_t* v1 = verts + ((size_t)OrenAVMGfxReadU32LE(tri) * 12u);
                    const uint8_t* v2 = verts + ((size_t)OrenAVMGfxReadU32LE(tri + 4) * 12u);
                    const uint8_t* v3 = verts + ((size_t)OrenAVMGfxReadU32LE(tri + 8) * 12u);
                    CGContextBeginPath(ctx);
                    CGContextMoveToPoint(ctx,
                                         OrenAVMGfxMesh3DModelCoord(v1, modelX, scaleMilli),
                                         OrenAVMGfxMesh3DModelCoord(v1 + 4, modelY, scaleMilli));
                    CGContextAddLineToPoint(ctx,
                                            OrenAVMGfxMesh3DModelCoord(v2, modelX, scaleMilli),
                                            OrenAVMGfxMesh3DModelCoord(v2 + 4, modelY, scaleMilli));
                    CGContextAddLineToPoint(ctx,
                                            OrenAVMGfxMesh3DModelCoord(v3, modelX, scaleMilli),
                                            OrenAVMGfxMesh3DModelCoord(v3 + 4, modelY, scaleMilli));
                    CGContextClosePath(ctx);
                    CGContextFillPath(ctx);
                }
            } else if (tris && scaleMilli != 0 && (meshStride == 36u || meshStride == 40u) && triangleCount == triangles.length / meshStride) {
                NSMutableData* orderData = nil;
                OrenAVMGfxTriangleOrder* order = OrenAVMGfxTriangleOrderBuffer(triangleCount, &orderData);
                if (!order) {
                    off += payloadLen;
                    continue;
                }
                uint32_t visibleCount = 0;
                for (uint32_t ti = 0; ti < triangleCount; ti++) {
                    int64_t z = OrenAVMGfxMesh3DZSumModel(tris + ((size_t)ti * meshStride), modelZ, scaleMilli);
                    if (!OrenAVMGfxMesh3DZVisible(z, depthEnabled, nearZ, farZ)) continue;
                    order[visibleCount++] = (OrenAVMGfxTriangleOrder){ti, z};
                }
                OrenAVMGfxSortTriangleOrder(order, visibleCount);
                if (materialRGBAValue || !mesh.hasRGBA) OrenAVMGfxSetFillColorValue(ctx, rgbaValue);
                for (uint32_t oi = 0; oi < visibleCount; oi++) {
                    const uint8_t* tri = tris + ((size_t)order[oi].triangle * meshStride);
                    if (!materialRGBAValue && mesh.hasRGBA) OrenAVMGfxSetFillColorBytes(ctx, tri + 36);
                    CGContextBeginPath(ctx);
                    CGContextMoveToPoint(ctx,
                                         OrenAVMGfxMesh3DModelCoord(tri, modelX, scaleMilli),
                                         OrenAVMGfxMesh3DModelCoord(tri + 4, modelY, scaleMilli));
                    CGContextAddLineToPoint(ctx,
                                            OrenAVMGfxMesh3DModelCoord(tri + 12, modelX, scaleMilli),
                                            OrenAVMGfxMesh3DModelCoord(tri + 16, modelY, scaleMilli));
                    CGContextAddLineToPoint(ctx,
                                            OrenAVMGfxMesh3DModelCoord(tri + 24, modelX, scaleMilli),
                                            OrenAVMGfxMesh3DModelCoord(tri + 28, modelY, scaleMilli));
                    CGContextClosePath(ctx);
                    CGContextFillPath(ctx);
                }
            }
        } else if (opcode == 85 && payloadLen == 4) {
            [self.orenMeshes removeObjectForKey:@(OrenAVMGfxReadU32LE(payload))];
        } else if (opcode == 89 && payloadLen == 8) {
            uint32_t materialID = OrenAVMGfxReadU32LE(payload);
            if (materialID != 0) self.orenMaterials3D[@(materialID)] = @(OrenAVMGfxRGBAValue(payload + 4));
        } else if (opcode == 92 && payloadLen == 4) {
            [self.orenMaterials3D removeObjectForKey:@(OrenAVMGfxReadU32LE(payload))];
        } else if (opcode == 93 && payloadLen == 28) {
            uint32_t modelID = OrenAVMGfxReadU32LE(payload);
            uint32_t meshID = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t scaleMilli = OrenAVMGfxReadU32LE(payload + 24);
            if (modelID != 0 && meshID != 0 && scaleMilli != 0) {
                self.orenModels3D[@(modelID)] = @{
                    @"mesh_id": @(meshID),
                    @"material_id": @(OrenAVMGfxReadU32LE(payload + 8)),
                    @"x": @((int32_t)OrenAVMGfxReadU32LE(payload + 12)),
                    @"y": @((int32_t)OrenAVMGfxReadU32LE(payload + 16)),
                    @"z": @((int32_t)OrenAVMGfxReadU32LE(payload + 20)),
                    @"scale_milli": @(scaleMilli)
                };
            }
        } else if (opcode == 95 && payloadLen == 4) {
            [self.orenModels3D removeObjectForKey:@(OrenAVMGfxReadU32LE(payload))];
        } else if (opcode == 86 && payloadLen >= 48 && ((payloadLen - 8) % 40) == 0) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t triangleCount = OrenAVMGfxReadU32LE(payload + 4);
            if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 8u) / 40u) {
                OrenAVMGfxMeshResource* mesh = [[OrenAVMGfxMeshResource alloc] init];
                mesh.triangles = [NSData dataWithBytes:payload + 8 length:(NSUInteger)payloadLen - 8u];
                mesh.triangleCount = triangleCount;
                mesh.stride = 40u;
                mesh.hasRGBA = YES;
                self.orenMeshes[@(meshID)] = mesh;
            }
        } else if (opcode == 88 && payloadLen >= 64) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t vertexCount = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t indexCount = OrenAVMGfxReadU32LE(payload + 12);
            size_t vertexBytes = (size_t)vertexCount * 12u;
            size_t indexBytes = (size_t)indexCount * 4u;
            BOOL indicesOK = meshID != 0 && vertexCount >= 3u && indexCount >= 3u && indexCount % 3u == 0 &&
                16u + vertexBytes + indexBytes == (size_t)payloadLen;
            for (uint32_t ii = 0; indicesOK && ii < indexCount; ii++) {
                if (OrenAVMGfxReadU32LE(payload + 16 + vertexBytes + ((size_t)ii * 4u)) >= vertexCount) {
                    indicesOK = NO;
                }
            }
            if (indicesOK) {
                OrenAVMGfxMeshResource* mesh = [[OrenAVMGfxMeshResource alloc] init];
                mesh.rgbaValue = OrenAVMGfxRGBAValue(payload + 4);
                mesh.vertices = [NSData dataWithBytes:payload + 16 length:vertexBytes];
                mesh.indices = [NSData dataWithBytes:payload + 16 + vertexBytes length:indexBytes];
                mesh.triangleCount = indexCount / 3u;
                mesh.indexCount = indexCount;
                self.orenMeshes[@(meshID)] = mesh;
            }
        } else if (opcode == 2 && payloadLen >= 16) {
            uint32_t x = OrenAVMGfxReadU32LE(payload);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t textLen = OrenAVMGfxReadU32LE(payload + 12);
            if (textLen <= (uint32_t)payloadLen - 16u) {
                NSString* text = [[NSString alloc] initWithBytes:payload + 16
                                                          length:(NSUInteger)textLen
                                                        encoding:NSUTF8StringEncoding];
                if (text) {
                    NSDictionary<NSAttributedStringKey, id>* attrs = OrenAVMGfxTextAttributes(OrenAVMGfxRGBAValue(payload + 8));
                    [text drawAtPoint:CGPointMake((CGFloat)x, (CGFloat)y) withAttributes:attrs];
                }
            }
        } else if (opcode == 68 && payloadLen >= 12) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            uint32_t textLen = OrenAVMGfxReadU32LE(payload + 8);
            if (textLen == (uint32_t)payloadLen - 12u) {
                NSString* text = [[NSString alloc] initWithBytes:payload + 12
                                                          length:(NSUInteger)textLen
                                                        encoding:NSUTF8StringEncoding];
                if (text) {
                    OrenAVMGfxTextResource* resource = [[OrenAVMGfxTextResource alloc] init];
                    resource.text = text;
                    resource.attributes = OrenAVMGfxTextAttributes(OrenAVMGfxRGBAValue(payload + 4));
                    self.orenTextResources[@(textID)] = resource;
                }
            }
        } else if (opcode == 69 && payloadLen == 12) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            uint32_t x = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 8);
            OrenAVMGfxTextResource* resource = self.orenTextResources[@(textID)];
            if (resource.text && resource.attributes) {
                [resource.text drawAtPoint:CGPointMake((CGFloat)x, (CGFloat)y) withAttributes:resource.attributes];
            }
        } else if (opcode == 72 && payloadLen >= 16 && ((payloadLen - 8) % 8) == 0) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            uint32_t posCount = OrenAVMGfxReadU32LE(payload + 4);
            OrenAVMGfxTextResource* resource = self.orenTextResources[@(textID)];
            if (resource.text && resource.attributes && posCount == ((uint32_t)payloadLen - 8u) / 8u) {
                for (uint32_t pi = 0; pi < posCount; pi++) {
                    const uint8_t* p = payload + 8 + ((size_t)pi * 8u);
                    [resource.text drawAtPoint:CGPointMake((CGFloat)OrenAVMGfxReadU32LE(p),
                                                           (CGFloat)OrenAVMGfxReadU32LE(p + 4))
                                withAttributes:resource.attributes];
                }
            }
        } else if (opcode == 70 && payloadLen == 4) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            [self.orenTextResources removeObjectForKey:@(textID)];
        } else if (opcode == 64 && payloadLen >= 16) {
            uint32_t imageID = OrenAVMGfxReadU32LE(payload);
            uint32_t iw = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t ih = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t imageLen = OrenAVMGfxReadU32LE(payload + 12);
            if (imageLen == (uint32_t)payloadLen - 16u) {
                UIImage* image = OrenAVMGfxImageRGBA(payload + 16, iw, ih, imageLen);
                [self orenPutImage:image imageID:imageID pixels:(NSUInteger)iw * (NSUInteger)ih];
            }
        } else if (opcode == 65 && payloadLen == 20) {
            uint32_t imageID = OrenAVMGfxReadU32LE(payload);
            uint32_t x = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t w = OrenAVMGfxReadU32LE(payload + 12);
            uint32_t h = OrenAVMGfxReadU32LE(payload + 16);
            UIImage* image = self.orenImages[@(imageID)].image;
            if (image) [image drawInRect:CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h)];
        } else if (opcode == 66 && payloadLen == 4) {
            uint32_t imageID = OrenAVMGfxReadU32LE(payload);
            [self orenRemoveImageWithID:imageID];
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
            UIImage* image = self.orenImages[@(imageID)].image;
            CGImageRef cgImage = image.CGImage;
            if (cgImage && OrenAVMGfxSubrectInImage(sx, sy, sw, sh, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage))) {
                CGImageRef subImage = CGImageCreateWithImageInRect(cgImage, CGRectMake((CGFloat)sx, (CGFloat)sy, (CGFloat)sw, (CGFloat)sh));
                if (subImage) {
                    UIImage* cropped = [UIImage imageWithCGImage:subImage];
                    [cropped drawInRect:CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h)];
                    CGImageRelease(subImage);
                }
            }
        } else if (opcode == 71 && payloadLen >= 40 && ((payloadLen - 8) % 32) == 0) {
            uint32_t imageID = OrenAVMGfxReadU32LE(payload);
            uint32_t rectCount = OrenAVMGfxReadU32LE(payload + 4);
            UIImage* image = self.orenImages[@(imageID)].image;
            CGImageRef cgImage = image.CGImage;
            if (cgImage && rectCount == ((uint32_t)payloadLen - 8u) / 32u) {
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
                    if (OrenAVMGfxSubrectInImage(sx, sy, sw, sh, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage))) {
                        CGImageRef subImage = CGImageCreateWithImageInRect(cgImage, CGRectMake((CGFloat)sx, (CGFloat)sy, (CGFloat)sw, (CGFloat)sh));
                        if (subImage) {
                            UIImage* cropped = [UIImage imageWithCGImage:subImage];
                            [cropped drawInRect:CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h)];
                            CGImageRelease(subImage);
                        }
                    }
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
