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

enum { OrenAVMGfxInlineTriangleOrderCapacity = 128 };

@interface OrenAVMGfxMeshResource : NSObject
@property(nonatomic) uint8_t* triangles;
@property(nonatomic) NSUInteger triangleBytes;
@property(nonatomic) uint8_t* vertices;
@property(nonatomic) NSUInteger vertexBytes;
@property(nonatomic) uint8_t* indices;
@property(nonatomic) NSUInteger indexBytes;
@property(nonatomic) uint32_t rgbaValue;
@property(nonatomic) uint32_t triangleCount;
@property(nonatomic) uint32_t indexCount;
@property(nonatomic) uint32_t stride;
@property(nonatomic) BOOL hasRGBA;
@end

@implementation OrenAVMGfxMeshResource
- (void)dealloc {
    free(_triangles);
    free(_vertices);
    free(_indices);
}
@end

@interface OrenAVMGfxTextResource : NSObject
@property(nonatomic, strong) NSAttributedString* attributedText;
@end

@implementation OrenAVMGfxTextResource
@end

@interface OrenAVMGfxImageResource : NSObject
@property(nonatomic, strong) UIImage* image;
@property(nonatomic) NSUInteger pixels;
@end

@implementation OrenAVMGfxImageResource
@end

@interface OrenAVMGfxModelResource : NSObject
@property(nonatomic) uint32_t meshID;
@property(nonatomic) uint32_t materialID;
@property(nonatomic) int32_t x;
@property(nonatomic) int32_t y;
@property(nonatomic) int32_t z;
@property(nonatomic) uint32_t scaleMilli;
@end

@implementation OrenAVMGfxModelResource
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

static uint8_t* OrenAVMGfxCopyPayloadBytes(const uint8_t* src, NSUInteger len) {
    if (len == 0) return NULL;
    uint8_t* out = (uint8_t*)malloc(len);
    if (!out) return NULL;
    memcpy(out, src, len);
    return out;
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

static OrenAVMGfxTriangleOrder* OrenAVMGfxTriangleOrderBuffer(uint32_t triangleCount,
                                                              OrenAVMGfxTriangleOrder* inlineOrder,
                                                              uint32_t inlineCapacity,
                                                              OrenAVMGfxTriangleOrder** heapStorage) {
    if (heapStorage) *heapStorage = NULL;
    if (triangleCount == 0) return NULL;
    if (inlineOrder && triangleCount <= inlineCapacity) return inlineOrder;
    if (!heapStorage || (NSUInteger)triangleCount > NSUIntegerMax / sizeof(OrenAVMGfxTriangleOrder)) return NULL;
    OrenAVMGfxTriangleOrder* bytes = (OrenAVMGfxTriangleOrder*)malloc((NSUInteger)triangleCount * sizeof(OrenAVMGfxTriangleOrder));
    if (!bytes) return NULL;
    *heapStorage = bytes;
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

static void OrenAVMGfxSetStrokeColorBytes(CGContextRef ctx, const uint8_t* rgba) {
    CGContextSetRGBStrokeColor(ctx,
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

static void OrenAVMGfxReleaseImageBytes(void* info, const void* data, size_t size) {
    (void)info;
    (void)size;
    free((void*)data);
}

static UIImage* OrenAVMGfxImageRGBA(const uint8_t* rgba, uint32_t width, uint32_t height, uint32_t byteCount) {
    uint64_t expected = (uint64_t)width * (uint64_t)height * 4ull;
    if (!rgba || width == 0 || height == 0 || expected != (uint64_t)byteCount) return nil;
    uint8_t* imageBytes = (uint8_t*)malloc((size_t)byteCount);
    if (!imageBytes) return nil;
    memcpy(imageBytes, rgba, (size_t)byteCount);
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, imageBytes, (size_t)byteCount, OrenAVMGfxReleaseImageBytes);
    if (!provider) {
        free(imageBytes);
        return nil;
    }
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

static void OrenAVMGfxDrawImageSubrect(CGImageRef cgImage,
                                       size_t imageWidth,
                                       size_t imageHeight,
                                       uint32_t sx,
                                       uint32_t sy,
                                       uint32_t sw,
                                       uint32_t sh,
                                       uint32_t x,
                                       uint32_t y,
                                       uint32_t w,
                                       uint32_t h) {
    if (!cgImage || !OrenAVMGfxSubrectInImage(sx, sy, sw, sh, imageWidth, imageHeight)) return;
    CGImageRef subImage = CGImageCreateWithImageInRect(cgImage, CGRectMake((CGFloat)sx, (CGFloat)sy, (CGFloat)sw, (CGFloat)sh));
    if (!subImage) return;
    UIImage* cropped = [UIImage imageWithCGImage:subImage];
    [cropped drawInRect:CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h)];
    CGImageRelease(subImage);
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

static const void* OrenAVMGfxRetainedImageKey(uint32_t imageID) {
    return (const void*)(uintptr_t)((uint64_t)imageID + 1ull);
}

static OrenAVMGfxImageResource* OrenAVMGfxRetainedImageResource(CFDictionaryRef images, uint32_t imageID) {
    if (!images || imageID == 0) return nil;
    return (__bridge OrenAVMGfxImageResource*)CFDictionaryGetValue(images, OrenAVMGfxRetainedImageKey(imageID));
}

static const void* OrenAVMGfxRetainedTextKey(uint32_t textID) {
    return (const void*)(uintptr_t)((uint64_t)textID + 1ull);
}

static OrenAVMGfxTextResource* OrenAVMGfxRetainedTextResource(CFDictionaryRef texts, uint32_t textID) {
    if (!texts || textID == 0) return nil;
    return (__bridge OrenAVMGfxTextResource*)CFDictionaryGetValue(texts, OrenAVMGfxRetainedTextKey(textID));
}

static const void* OrenAVMGfxRetainedMeshKey(uint32_t meshID) {
    return (const void*)(uintptr_t)((uint64_t)meshID + 1ull);
}

static OrenAVMGfxMeshResource* OrenAVMGfxRetainedMeshResource(CFDictionaryRef meshes, uint32_t meshID) {
    if (!meshes || meshID == 0) return nil;
    return (__bridge OrenAVMGfxMeshResource*)CFDictionaryGetValue(meshes, OrenAVMGfxRetainedMeshKey(meshID));
}

static const void* OrenAVMGfxRetainedMaterialKey(uint32_t materialID) {
    return (const void*)(uintptr_t)((uint64_t)materialID + 1ull);
}

static const void* OrenAVMGfxRetainedMaterialValue(uint32_t rgbaValue) {
    return (const void*)(uintptr_t)((uint64_t)rgbaValue + 1ull);
}

static BOOL OrenAVMGfxRetainedMaterialRGBA(CFDictionaryRef materials, uint32_t materialID, uint32_t* rgbaOut) {
    const void* stored = NULL;
    if (!materials || materialID == 0 || !CFDictionaryGetValueIfPresent(materials, OrenAVMGfxRetainedMaterialKey(materialID), &stored)) {
        return NO;
    }
    if (rgbaOut) *rgbaOut = (uint32_t)((uintptr_t)stored - 1ull);
    return YES;
}

static const void* OrenAVMGfxRetainedModelKey(uint32_t modelID) {
    return (const void*)(uintptr_t)((uint64_t)modelID + 1ull);
}

static OrenAVMGfxModelResource* OrenAVMGfxRetainedModelResource(CFDictionaryRef models, uint32_t modelID) {
    if (!models || modelID == 0) return nil;
    return (__bridge OrenAVMGfxModelResource*)CFDictionaryGetValue(models, OrenAVMGfxRetainedModelKey(modelID));
}

@interface OrenAVMGraphicsView () {
    CFMutableDictionaryRef _orenTouchIDs;
    CFMutableDictionaryRef _orenTextResourcesByID;
    CFMutableDictionaryRef _orenMeshesByID;
    CFMutableDictionaryRef _orenMaterials3DByID;
    CFMutableDictionaryRef _orenModels3DByID;
    CFMutableDictionaryRef _orenImagesByID;
}
@property(nonatomic) uint32_t orenNextTouchID;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, NSDictionary<NSAttributedStringKey, id>*>* orenTextAttributes;
@property(nonatomic) uint32_t orenLastTextAttributesRGBA;
@property(nonatomic, strong) NSDictionary<NSAttributedStringKey, id>* orenLastTextAttributes;
@property(nonatomic, readwrite) NSUInteger retainedImagePixelCount;
@property(nonatomic, strong) id orenGraphicsFrameObserverToken;
@property(nonatomic) BOOL orenFrameReloadScheduled;
@end

static NSDictionary<NSAttributedStringKey, id>* OrenAVMGfxTextAttributesForView(OrenAVMGraphicsView* view, uint32_t rgbaValue) {
    if (view.orenLastTextAttributes && view.orenLastTextAttributesRGBA == rgbaValue) return view.orenLastTextAttributes;
    if (!view.orenTextAttributes) view.orenTextAttributes = [NSMutableDictionary dictionary];
    NSNumber* key = @(rgbaValue);
    NSDictionary<NSAttributedStringKey, id>* attrs = view.orenTextAttributes[key];
    if (!attrs) {
        attrs = OrenAVMGfxTextAttributes(rgbaValue);
        view.orenTextAttributes[key] = attrs;
    }
    view.orenLastTextAttributesRGBA = rgbaValue;
    view.orenLastTextAttributes = attrs;
    return attrs;
}

@implementation OrenAVMGraphicsView

- (void)orenConfigureGraphicsView {
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.multipleTouchEnabled = YES;
    if (!_orenTouchIDs) _orenTouchIDs = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    if (self.orenNextTouchID == 0) self.orenNextTouchID = 1u;
    if (!_orenTextResourcesByID) _orenTextResourcesByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!self.orenTextAttributes) self.orenTextAttributes = [NSMutableDictionary dictionary];
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

- (void)orenRemoveImageWithID:(uint32_t)imageID {
    if (imageID == 0 || !_orenImagesByID) return;
    const void* key = OrenAVMGfxRetainedImageKey(imageID);
    OrenAVMGfxImageResource* old = OrenAVMGfxRetainedImageResource(_orenImagesByID, imageID);
    if (old) {
        NSUInteger pixels = old.pixels;
        self.retainedImagePixelCount = self.retainedImagePixelCount > pixels ? self.retainedImagePixelCount - pixels : 0;
    }
    CFDictionaryRemoveValue(_orenImagesByID, key);
}

- (void)orenPutImage:(UIImage*)image imageID:(uint32_t)imageID pixels:(NSUInteger)pixels {
    if (!image || imageID == 0) return;
    const void* key = OrenAVMGfxRetainedImageKey(imageID);
    OrenAVMGfxImageResource* oldResource = OrenAVMGfxRetainedImageResource(_orenImagesByID, imageID);
    NSUInteger oldPixels = oldResource ? oldResource.pixels : 0;
    NSUInteger imageCount = _orenImagesByID ? (NSUInteger)CFDictionaryGetCount(_orenImagesByID) : 0;
    NSUInteger countAfter = oldResource ? imageCount : imageCount + 1u;
    NSUInteger retainedAfterOld = self.retainedImagePixelCount >= oldPixels ? self.retainedImagePixelCount - oldPixels : 0;
    if (pixels > NSUIntegerMax - retainedAfterOld) return;
    NSUInteger pixelAfter = retainedAfterOld + pixels;
    if (self.retainedImageCountLimit == 0 || countAfter > self.retainedImageCountLimit) return;
    if (self.retainedImagePixelLimit == 0 || pixels > self.retainedImagePixelLimit || pixelAfter > self.retainedImagePixelLimit) return;
    OrenAVMGfxImageResource* resource = [[OrenAVMGfxImageResource alloc] init];
    resource.image = image;
    resource.pixels = pixels;
    if (!_orenImagesByID) _orenImagesByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!_orenImagesByID) return;
    CFDictionarySetValue(_orenImagesByID, key, (__bridge const void*)resource);
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
                OrenAVMGfxMeshResource* mesh = [[OrenAVMGfxMeshResource alloc] init];
                mesh.rgbaValue = OrenAVMGfxRGBAValue(payload + 4);
                mesh.triangleBytes = (NSUInteger)payloadLen - 12u;
                mesh.triangles = OrenAVMGfxCopyPayloadBytes(payload + 12, mesh.triangleBytes);
                if (!mesh.triangles) {
                    off += payloadLen;
                    continue;
                }
                mesh.triangleCount = triangleCount;
                mesh.stride = 24u;
                if (_orenMeshesByID) CFDictionarySetValue(_orenMeshesByID, OrenAVMGfxRetainedMeshKey(meshID), (__bridge const void*)mesh);
            }
        } else if (opcode == 81 && payloadLen == 4) {
            OrenAVMGfxMeshResource* mesh = OrenAVMGfxRetainedMeshResource(_orenMeshesByID, OrenAVMGfxReadU32LE(payload));
            const uint8_t* tris = mesh.triangles;
            if (tris && mesh.triangleCount == mesh.triangleBytes / 24u) {
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
            if (_orenMeshesByID) CFDictionaryRemoveValue(_orenMeshesByID, OrenAVMGfxRetainedMeshKey(OrenAVMGfxReadU32LE(payload)));
        } else if (opcode == 83 && payloadLen >= 48 && ((payloadLen - 12) % 36) == 0) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t triangleCount = OrenAVMGfxReadU32LE(payload + 8);
            if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 12u) / 36u) {
                OrenAVMGfxMeshResource* mesh = [[OrenAVMGfxMeshResource alloc] init];
                mesh.rgbaValue = OrenAVMGfxRGBAValue(payload + 4);
                mesh.triangleBytes = (NSUInteger)payloadLen - 12u;
                mesh.triangles = OrenAVMGfxCopyPayloadBytes(payload + 12, mesh.triangleBytes);
                if (!mesh.triangles) {
                    off += payloadLen;
                    continue;
                }
                mesh.triangleCount = triangleCount;
                mesh.stride = 36u;
                if (_orenMeshesByID) CFDictionarySetValue(_orenMeshesByID, OrenAVMGfxRetainedMeshKey(meshID), (__bridge const void*)mesh);
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
                OrenAVMGfxModelResource* model = OrenAVMGfxRetainedModelResource(_orenModels3DByID, meshID);
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
            OrenAVMGfxMeshResource* mesh = OrenAVMGfxRetainedMeshResource(_orenMeshesByID, meshID);
            BOOL hasMaterialRGBA = NO;
            uint32_t materialRGBAOverride = 0;
            if (opcode == 90 || opcode == 91) {
                materialID = OrenAVMGfxReadU32LE(payload + 4);
            }
            if (materialID != 0) {
                hasMaterialRGBA = OrenAVMGfxRetainedMaterialRGBA(_orenMaterials3DByID, materialID, &materialRGBAOverride);
                if (!hasMaterialRGBA) {
                    off += payloadLen;
                    continue;
                }
            }
            const uint8_t* tris = mesh.triangles;
            const uint8_t* verts = mesh.vertices;
            const uint8_t* idx = mesh.indices;
            uint32_t meshStride = mesh.stride;
            uint32_t triangleCount = mesh.triangleCount;
            uint32_t rgbaValue = hasMaterialRGBA ? materialRGBAOverride : mesh.rgbaValue;
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
            if (verts && idx && scaleMilli != 0 && triangleCount == mesh.indexBytes / 12u && mesh.vertexBytes % 12u == 0) {
                OrenAVMGfxTriangleOrder inlineOrder[OrenAVMGfxInlineTriangleOrderCapacity];
                OrenAVMGfxTriangleOrder* heapOrder = NULL;
                OrenAVMGfxTriangleOrder* order = OrenAVMGfxTriangleOrderBuffer(triangleCount,
                                                                               inlineOrder,
                                                                               OrenAVMGfxInlineTriangleOrderCapacity,
                                                                               &heapOrder);
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
                free(heapOrder);
            } else if (tris && scaleMilli != 0 && (meshStride == 36u || meshStride == 40u) && triangleCount == mesh.triangleBytes / meshStride) {
                OrenAVMGfxTriangleOrder inlineOrder[OrenAVMGfxInlineTriangleOrderCapacity];
                OrenAVMGfxTriangleOrder* heapOrder = NULL;
                OrenAVMGfxTriangleOrder* order = OrenAVMGfxTriangleOrderBuffer(triangleCount,
                                                                               inlineOrder,
                                                                               OrenAVMGfxInlineTriangleOrderCapacity,
                                                                               &heapOrder);
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
                if (hasMaterialRGBA || !mesh.hasRGBA) OrenAVMGfxSetFillColorValue(ctx, rgbaValue);
                for (uint32_t oi = 0; oi < visibleCount; oi++) {
                    const uint8_t* tri = tris + ((size_t)order[oi].triangle * meshStride);
                    if (!hasMaterialRGBA && mesh.hasRGBA) OrenAVMGfxSetFillColorBytes(ctx, tri + 36);
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
                free(heapOrder);
            }
        } else if (opcode == 85 && payloadLen == 4) {
            if (_orenMeshesByID) CFDictionaryRemoveValue(_orenMeshesByID, OrenAVMGfxRetainedMeshKey(OrenAVMGfxReadU32LE(payload)));
        } else if (opcode == 89 && payloadLen == 8) {
            uint32_t materialID = OrenAVMGfxReadU32LE(payload);
            if (materialID != 0) {
                if (!_orenMaterials3DByID) _orenMaterials3DByID = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
                if (_orenMaterials3DByID) {
                    CFDictionarySetValue(_orenMaterials3DByID,
                                         OrenAVMGfxRetainedMaterialKey(materialID),
                                         OrenAVMGfxRetainedMaterialValue(OrenAVMGfxRGBAValue(payload + 4)));
                }
            }
        } else if (opcode == 92 && payloadLen == 4) {
            if (_orenMaterials3DByID) CFDictionaryRemoveValue(_orenMaterials3DByID, OrenAVMGfxRetainedMaterialKey(OrenAVMGfxReadU32LE(payload)));
        } else if (opcode == 93 && payloadLen == 28) {
            uint32_t modelID = OrenAVMGfxReadU32LE(payload);
            uint32_t meshID = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t scaleMilli = OrenAVMGfxReadU32LE(payload + 24);
            if (modelID != 0 && meshID != 0 && scaleMilli != 0) {
                OrenAVMGfxModelResource* model = [[OrenAVMGfxModelResource alloc] init];
                model.meshID = meshID;
                model.materialID = OrenAVMGfxReadU32LE(payload + 8);
                model.x = (int32_t)OrenAVMGfxReadU32LE(payload + 12);
                model.y = (int32_t)OrenAVMGfxReadU32LE(payload + 16);
                model.z = (int32_t)OrenAVMGfxReadU32LE(payload + 20);
                model.scaleMilli = scaleMilli;
                if (!_orenModels3DByID) _orenModels3DByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
                if (_orenModels3DByID) {
                    CFDictionarySetValue(_orenModels3DByID, OrenAVMGfxRetainedModelKey(modelID), (__bridge const void*)model);
                }
            }
        } else if (opcode == 95 && payloadLen == 4) {
            if (_orenModels3DByID) CFDictionaryRemoveValue(_orenModels3DByID, OrenAVMGfxRetainedModelKey(OrenAVMGfxReadU32LE(payload)));
        } else if (opcode == 86 && payloadLen >= 48 && ((payloadLen - 8) % 40) == 0) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t triangleCount = OrenAVMGfxReadU32LE(payload + 4);
            if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 8u) / 40u) {
                OrenAVMGfxMeshResource* mesh = [[OrenAVMGfxMeshResource alloc] init];
                mesh.triangleBytes = (NSUInteger)payloadLen - 8u;
                mesh.triangles = OrenAVMGfxCopyPayloadBytes(payload + 8, mesh.triangleBytes);
                if (!mesh.triangles) {
                    off += payloadLen;
                    continue;
                }
                mesh.triangleCount = triangleCount;
                mesh.stride = 40u;
                mesh.hasRGBA = YES;
                if (_orenMeshesByID) CFDictionarySetValue(_orenMeshesByID, OrenAVMGfxRetainedMeshKey(meshID), (__bridge const void*)mesh);
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
                mesh.vertexBytes = vertexBytes;
                mesh.indexBytes = indexBytes;
                mesh.vertices = OrenAVMGfxCopyPayloadBytes(payload + 16, mesh.vertexBytes);
                mesh.indices = OrenAVMGfxCopyPayloadBytes(payload + 16 + vertexBytes, mesh.indexBytes);
                if (!mesh.vertices || !mesh.indices) {
                    off += payloadLen;
                    continue;
                }
                mesh.triangleCount = indexCount / 3u;
                mesh.indexCount = indexCount;
                if (_orenMeshesByID) CFDictionarySetValue(_orenMeshesByID, OrenAVMGfxRetainedMeshKey(meshID), (__bridge const void*)mesh);
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
                    NSDictionary<NSAttributedStringKey, id>* attrs = OrenAVMGfxTextAttributesForView(self, OrenAVMGfxRGBAValue(payload + 8));
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
                    resource.attributedText = [[NSAttributedString alloc] initWithString:text
                                                                               attributes:OrenAVMGfxTextAttributesForView(self, OrenAVMGfxRGBAValue(payload + 4))];
                    if (!_orenTextResourcesByID) _orenTextResourcesByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
                    if (_orenTextResourcesByID) {
                        CFDictionarySetValue(_orenTextResourcesByID, OrenAVMGfxRetainedTextKey(textID), (__bridge const void*)resource);
                    }
                }
            }
        } else if (opcode == 69 && payloadLen == 12) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            uint32_t x = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 8);
            OrenAVMGfxTextResource* resource = OrenAVMGfxRetainedTextResource(_orenTextResourcesByID, textID);
            if (resource.attributedText) {
                [resource.attributedText drawAtPoint:CGPointMake((CGFloat)x, (CGFloat)y)];
            }
        } else if (opcode == 72 && payloadLen >= 16 && ((payloadLen - 8) % 8) == 0) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            uint32_t posCount = OrenAVMGfxReadU32LE(payload + 4);
            OrenAVMGfxTextResource* resource = OrenAVMGfxRetainedTextResource(_orenTextResourcesByID, textID);
            if (resource.attributedText && posCount == ((uint32_t)payloadLen - 8u) / 8u) {
                for (uint32_t pi = 0; pi < posCount; pi++) {
                    const uint8_t* p = payload + 8 + ((size_t)pi * 8u);
                    [resource.attributedText drawAtPoint:CGPointMake((CGFloat)OrenAVMGfxReadU32LE(p),
                                                                    (CGFloat)OrenAVMGfxReadU32LE(p + 4))];
                }
            }
        } else if (opcode == 70 && payloadLen == 4) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            if (_orenTextResourcesByID) CFDictionaryRemoveValue(_orenTextResourcesByID, OrenAVMGfxRetainedTextKey(textID));
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
            UIImage* image = OrenAVMGfxRetainedImageResource(_orenImagesByID, imageID).image;
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
