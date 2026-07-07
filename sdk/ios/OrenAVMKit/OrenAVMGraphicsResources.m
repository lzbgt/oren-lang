#import "OrenAVMGraphicsResources.h"

#if TARGET_OS_IPHONE

#import <dispatch/dispatch.h>
#include <stdlib.h>
#include <string.h>

@implementation OrenAVMGfxMeshResource
- (void)dealloc {
    free(_triangles);
    free(_vertices);
    free(_indices);
}
@end

@implementation OrenAVMGfxTextResource
@end

@implementation OrenAVMGfxImageResource
@end

@implementation OrenAVMGfxModelResource
@end

static uint32_t OrenAVMGfxResourceReadU32LE(const uint8_t* p) {
    return (uint32_t)p[0] |
        ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) |
        ((uint32_t)p[3] << 24);
}

static const void* OrenAVMGfxRetainedKey(uint32_t idValue) {
    return (const void*)(uintptr_t)((uint64_t)idValue + 1ull);
}

uint8_t* OrenAVMGfxCopyPayloadBytes(const uint8_t* src, NSUInteger len) {
    if (len == 0) return NULL;
    uint8_t* out = (uint8_t*)malloc(len);
    if (!out) return NULL;
    memcpy(out, src, len);
    return out;
}

const void* OrenAVMGfxRetainedImageKey(uint32_t imageID) {
    return OrenAVMGfxRetainedKey(imageID);
}

OrenAVMGfxImageResource* OrenAVMGfxRetainedImageResource(CFDictionaryRef images, uint32_t imageID) {
    if (!images || imageID == 0) return nil;
    return (__bridge OrenAVMGfxImageResource*)CFDictionaryGetValue(images, OrenAVMGfxRetainedImageKey(imageID));
}

static void OrenAVMGfxReleaseImageBytes(void* info, const void* data, size_t size) {
    (void)info;
    (void)size;
    free((void*)data);
}

UIImage* OrenAVMGfxImageRGBA(const uint8_t* rgba, uint32_t width, uint32_t height, uint32_t byteCount) {
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

BOOL OrenAVMGfxPutImageResource(CFMutableDictionaryRef* imagesByID,
                                UIImage* image,
                                uint32_t imageID,
                                NSUInteger pixels,
                                NSUInteger retainedImageCountLimit,
                                NSUInteger retainedImagePixelLimit,
                                NSUInteger* retainedImagePixelCount) {
    if (!imagesByID || !image || imageID == 0 || !retainedImagePixelCount) return NO;
    const void* key = OrenAVMGfxRetainedImageKey(imageID);
    OrenAVMGfxImageResource* oldResource = OrenAVMGfxRetainedImageResource(*imagesByID, imageID);
    NSUInteger oldPixels = oldResource ? oldResource.pixels : 0;
    NSUInteger imageCount = *imagesByID ? (NSUInteger)CFDictionaryGetCount(*imagesByID) : 0;
    NSUInteger countAfter = oldResource ? imageCount : imageCount + 1u;
    NSUInteger retainedAfterOld = *retainedImagePixelCount >= oldPixels ? *retainedImagePixelCount - oldPixels : 0;
    if (pixels > NSUIntegerMax - retainedAfterOld) return NO;
    NSUInteger pixelAfter = retainedAfterOld + pixels;
    if (retainedImageCountLimit == 0 || countAfter > retainedImageCountLimit) return NO;
    if (retainedImagePixelLimit == 0 || pixels > retainedImagePixelLimit || pixelAfter > retainedImagePixelLimit) return NO;
    OrenAVMGfxImageResource* resource = [[OrenAVMGfxImageResource alloc] init];
    resource.image = image;
    resource.pixels = pixels;
    if (!*imagesByID) *imagesByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!*imagesByID) return NO;
    CFDictionarySetValue(*imagesByID, key, (__bridge const void*)resource);
    *retainedImagePixelCount = pixelAfter;
    return YES;
}

void OrenAVMGfxRemoveImageResource(CFMutableDictionaryRef imagesByID,
                                   uint32_t imageID,
                                   NSUInteger* retainedImagePixelCount) {
    if (imageID == 0 || !imagesByID) return;
    OrenAVMGfxImageResource* old = OrenAVMGfxRetainedImageResource(imagesByID, imageID);
    if (old && retainedImagePixelCount) {
        NSUInteger pixels = old.pixels;
        *retainedImagePixelCount = *retainedImagePixelCount > pixels ? *retainedImagePixelCount - pixels : 0;
    }
    CFDictionaryRemoveValue(imagesByID, OrenAVMGfxRetainedImageKey(imageID));
}

static BOOL OrenAVMGfxSubrectInImage(uint32_t sx, uint32_t sy, uint32_t sw, uint32_t sh, size_t width, size_t height) {
    return (uint64_t)sx + (uint64_t)sw <= (uint64_t)width &&
        (uint64_t)sy + (uint64_t)sh <= (uint64_t)height;
}

void OrenAVMGfxDrawImageSubrect(CGImageRef cgImage,
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

const void* OrenAVMGfxRetainedTextKey(uint32_t textID) {
    return OrenAVMGfxRetainedKey(textID);
}

OrenAVMGfxTextResource* OrenAVMGfxRetainedTextResource(CFDictionaryRef texts, uint32_t textID) {
    if (!texts || textID == 0) return nil;
    return (__bridge OrenAVMGfxTextResource*)CFDictionaryGetValue(texts, OrenAVMGfxRetainedTextKey(textID));
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

static const void* OrenAVMGfxTextAttributeKey(uint32_t rgbaValue) {
    return OrenAVMGfxRetainedKey(rgbaValue);
}

static NSDictionary<NSAttributedStringKey, id>* OrenAVMGfxTextAttributes(uint32_t rgbaValue) {
    return @{
        NSForegroundColorAttributeName: OrenAVMGfxColorValue(rgbaValue),
        NSFontAttributeName: OrenAVMGfxTextFont()
    };
}

NSDictionary<NSAttributedStringKey, id>* OrenAVMGfxTextAttributesForRGBA(CFMutableDictionaryRef* attrsByRGBA,
                                                                         uint32_t* lastRGBA,
                                                                         NSDictionary<NSAttributedStringKey, id>* __strong* lastAttributes,
                                                                         uint32_t rgbaValue) {
    if (lastRGBA && lastAttributes && *lastAttributes && *lastRGBA == rgbaValue) return *lastAttributes;
    if (attrsByRGBA && !*attrsByRGBA) *attrsByRGBA = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    const void* key = OrenAVMGfxTextAttributeKey(rgbaValue);
    NSDictionary<NSAttributedStringKey, id>* attrs = attrsByRGBA && *attrsByRGBA ?
        (__bridge NSDictionary<NSAttributedStringKey, id>*)CFDictionaryGetValue(*attrsByRGBA, key) : nil;
    if (!attrs) {
        attrs = OrenAVMGfxTextAttributes(rgbaValue);
        if (attrsByRGBA && *attrsByRGBA) CFDictionarySetValue(*attrsByRGBA, key, (__bridge const void*)attrs);
    }
    if (lastRGBA) *lastRGBA = rgbaValue;
    if (lastAttributes) *lastAttributes = attrs;
    return attrs;
}

void OrenAVMGfxDrawTextBytes(const uint8_t* textBytes,
                             uint32_t textLen,
                             uint32_t x,
                             uint32_t y,
                             NSDictionary<NSAttributedStringKey, id>* attrs) {
    if (!textBytes || !attrs) return;
    NSString* text = [[NSString alloc] initWithBytes:textBytes length:(NSUInteger)textLen encoding:NSUTF8StringEncoding];
    if (text) [text drawAtPoint:CGPointMake((CGFloat)x, (CGFloat)y) withAttributes:attrs];
}

BOOL OrenAVMGfxPutTextResource(CFMutableDictionaryRef* texts,
                               uint32_t textID,
                               const uint8_t* textBytes,
                               uint32_t textLen,
                               NSDictionary<NSAttributedStringKey, id>* attrs) {
    if (!texts || textID == 0 || !textBytes || !attrs) return NO;
    NSString* text = [[NSString alloc] initWithBytes:textBytes length:(NSUInteger)textLen encoding:NSUTF8StringEncoding];
    if (!text) return NO;
    OrenAVMGfxTextResource* resource = [[OrenAVMGfxTextResource alloc] init];
    resource.attributedText = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    if (!*texts) *texts = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!*texts) return NO;
    CFDictionarySetValue(*texts, OrenAVMGfxRetainedTextKey(textID), (__bridge const void*)resource);
    return YES;
}

void OrenAVMGfxDrawTextResource(CFDictionaryRef texts, uint32_t textID, uint32_t x, uint32_t y) {
    OrenAVMGfxTextResource* resource = OrenAVMGfxRetainedTextResource(texts, textID);
    if (resource.attributedText) [resource.attributedText drawAtPoint:CGPointMake((CGFloat)x, (CGFloat)y)];
}

void OrenAVMGfxDrawTextResourcePositions(CFDictionaryRef texts,
                                         uint32_t textID,
                                         const uint8_t* positions,
                                         uint32_t posCount) {
    OrenAVMGfxTextResource* resource = OrenAVMGfxRetainedTextResource(texts, textID);
    if (!resource.attributedText || !positions) return;
    for (uint32_t pi = 0; pi < posCount; pi++) {
        const uint8_t* p = positions + ((size_t)pi * 8u);
        [resource.attributedText drawAtPoint:CGPointMake((CGFloat)OrenAVMGfxResourceReadU32LE(p),
                                                        (CGFloat)OrenAVMGfxResourceReadU32LE(p + 4))];
    }
}

void OrenAVMGfxRemoveTextResource(CFMutableDictionaryRef texts, uint32_t textID) {
    if (texts && textID != 0) CFDictionaryRemoveValue(texts, OrenAVMGfxRetainedTextKey(textID));
}

const void* OrenAVMGfxRetainedMeshKey(uint32_t meshID) {
    return OrenAVMGfxRetainedKey(meshID);
}

OrenAVMGfxMeshResource* OrenAVMGfxRetainedMeshResource(CFDictionaryRef meshes, uint32_t meshID) {
    if (!meshes || meshID == 0) return nil;
    return (__bridge OrenAVMGfxMeshResource*)CFDictionaryGetValue(meshes, OrenAVMGfxRetainedMeshKey(meshID));
}

static BOOL OrenAVMGfxEnsureRetainedResourceMap(CFMutableDictionaryRef* map) {
    if (!map) return NO;
    if (!*map) *map = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    return *map != NULL;
}

static BOOL OrenAVMGfxEnsureScalarResourceMap(CFMutableDictionaryRef* map) {
    if (!map) return NO;
    if (!*map) *map = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    return *map != NULL;
}

BOOL OrenAVMGfxPutTriangleMeshResource(CFMutableDictionaryRef* meshes,
                                       uint32_t meshID,
                                       uint32_t rgbaValue,
                                       const uint8_t* triangles,
                                       NSUInteger triangleBytes,
                                       uint32_t triangleCount,
                                       uint32_t stride,
                                       BOOL hasRGBA) {
    if (meshID == 0 || !triangles || stride == 0 || triangleCount == 0 || triangleBytes != (NSUInteger)triangleCount * (NSUInteger)stride) return NO;
    OrenAVMGfxMeshResource* mesh = [[OrenAVMGfxMeshResource alloc] init];
    mesh.rgbaValue = rgbaValue;
    mesh.triangleBytes = triangleBytes;
    mesh.triangles = OrenAVMGfxCopyPayloadBytes(triangles, triangleBytes);
    if (!mesh.triangles) return NO;
    mesh.triangleCount = triangleCount;
    mesh.stride = stride;
    mesh.hasRGBA = hasRGBA;
    if (!OrenAVMGfxEnsureRetainedResourceMap(meshes)) return NO;
    CFDictionarySetValue(*meshes, OrenAVMGfxRetainedMeshKey(meshID), (__bridge const void*)mesh);
    return YES;
}

BOOL OrenAVMGfxPutIndexedMeshResource(CFMutableDictionaryRef* meshes,
                                      uint32_t meshID,
                                      uint32_t rgbaValue,
                                      const uint8_t* vertices,
                                      NSUInteger vertexBytes,
                                      uint32_t vertexCount,
                                      const uint8_t* indices,
                                      NSUInteger indexBytes,
                                      uint32_t indexCount) {
    if (meshID == 0 || !vertices || !indices || vertexCount < 3u || indexCount < 3u || (indexCount % 3u) != 0) return NO;
    if (vertexBytes != (NSUInteger)vertexCount * 12u || indexBytes != (NSUInteger)indexCount * 4u) return NO;
    for (uint32_t ii = 0; ii < indexCount; ii++) {
        if (OrenAVMGfxResourceReadU32LE(indices + ((size_t)ii * 4u)) >= vertexCount) return NO;
    }
    OrenAVMGfxMeshResource* mesh = [[OrenAVMGfxMeshResource alloc] init];
    mesh.rgbaValue = rgbaValue;
    mesh.vertexBytes = vertexBytes;
    mesh.indexBytes = indexBytes;
    mesh.vertices = OrenAVMGfxCopyPayloadBytes(vertices, mesh.vertexBytes);
    mesh.indices = OrenAVMGfxCopyPayloadBytes(indices, mesh.indexBytes);
    if (!mesh.vertices || !mesh.indices) return NO;
    mesh.triangleCount = indexCount / 3u;
    mesh.indexCount = indexCount;
    if (!OrenAVMGfxEnsureRetainedResourceMap(meshes)) return NO;
    CFDictionarySetValue(*meshes, OrenAVMGfxRetainedMeshKey(meshID), (__bridge const void*)mesh);
    return YES;
}

void OrenAVMGfxRemoveMeshResource(CFMutableDictionaryRef meshes, uint32_t meshID) {
    if (meshes && meshID != 0) CFDictionaryRemoveValue(meshes, OrenAVMGfxRetainedMeshKey(meshID));
}

const void* OrenAVMGfxRetainedMaterialKey(uint32_t materialID) {
    return OrenAVMGfxRetainedKey(materialID);
}

const void* OrenAVMGfxRetainedMaterialValue(uint32_t rgbaValue) {
    return (const void*)(uintptr_t)((uint64_t)rgbaValue + 1ull);
}

BOOL OrenAVMGfxRetainedMaterialRGBA(CFDictionaryRef materials, uint32_t materialID, uint32_t* rgbaOut) {
    const void* stored = NULL;
    if (!materials || materialID == 0 || !CFDictionaryGetValueIfPresent(materials, OrenAVMGfxRetainedMaterialKey(materialID), &stored)) {
        return NO;
    }
    if (rgbaOut) *rgbaOut = (uint32_t)((uintptr_t)stored - 1ull);
    return YES;
}

BOOL OrenAVMGfxPutMaterialResource(CFMutableDictionaryRef* materials, uint32_t materialID, uint32_t rgbaValue) {
    if (materialID == 0) return NO;
    if (!OrenAVMGfxEnsureScalarResourceMap(materials)) return NO;
    CFDictionarySetValue(*materials, OrenAVMGfxRetainedMaterialKey(materialID), OrenAVMGfxRetainedMaterialValue(rgbaValue));
    return YES;
}

void OrenAVMGfxRemoveMaterialResource(CFMutableDictionaryRef materials, uint32_t materialID) {
    if (materials && materialID != 0) CFDictionaryRemoveValue(materials, OrenAVMGfxRetainedMaterialKey(materialID));
}

const void* OrenAVMGfxRetainedModelKey(uint32_t modelID) {
    return OrenAVMGfxRetainedKey(modelID);
}

OrenAVMGfxModelResource* OrenAVMGfxRetainedModelResource(CFDictionaryRef models, uint32_t modelID) {
    if (!models || modelID == 0) return nil;
    return (__bridge OrenAVMGfxModelResource*)CFDictionaryGetValue(models, OrenAVMGfxRetainedModelKey(modelID));
}

BOOL OrenAVMGfxPutModelResource(CFMutableDictionaryRef* models,
                                uint32_t modelID,
                                uint32_t meshID,
                                uint32_t materialID,
                                int32_t x,
                                int32_t y,
                                int32_t z,
                                uint32_t scaleMilli) {
    if (modelID == 0 || meshID == 0 || scaleMilli == 0) return NO;
    OrenAVMGfxModelResource* model = [[OrenAVMGfxModelResource alloc] init];
    model.meshID = meshID;
    model.materialID = materialID;
    model.x = x;
    model.y = y;
    model.z = z;
    model.scaleMilli = scaleMilli;
    if (!OrenAVMGfxEnsureRetainedResourceMap(models)) return NO;
    CFDictionarySetValue(*models, OrenAVMGfxRetainedModelKey(modelID), (__bridge const void*)model);
    return YES;
}

void OrenAVMGfxRemoveModelResource(CFMutableDictionaryRef models, uint32_t modelID) {
    if (models && modelID != 0) CFDictionaryRemoveValue(models, OrenAVMGfxRetainedModelKey(modelID));
}

static int64_t OrenAVMGfxMesh3DZSum(const uint8_t* tri) {
    return (int64_t)(int32_t)OrenAVMGfxResourceReadU32LE(tri + 8) +
        (int64_t)(int32_t)OrenAVMGfxResourceReadU32LE(tri + 20) +
        (int64_t)(int32_t)OrenAVMGfxResourceReadU32LE(tri + 32);
}

int64_t OrenAVMGfxMesh3DZSumModel(const uint8_t* tri, int32_t offset, uint32_t scaleMilli) {
    return (OrenAVMGfxMesh3DZSum(tri) * (int64_t)scaleMilli) / 1000 + (int64_t)offset * 3;
}

BOOL OrenAVMGfxMesh3DZVisible(int64_t zsum, BOOL depthEnabled, int32_t nearZ, int32_t farZ) {
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

OrenAVMGfxTriangleOrder* OrenAVMGfxTriangleOrderBuffer(uint32_t triangleCount,
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

void OrenAVMGfxSortTriangleOrder(OrenAVMGfxTriangleOrder* order, uint32_t count) {
    if (count > 1) qsort(order, count, sizeof(OrenAVMGfxTriangleOrder), OrenAVMGfxTriangleOrderCompare);
}

int64_t OrenAVMGfxMesh3DIndexedZSumModel(const uint8_t* vertices,
                                         const uint8_t* indices,
                                         uint32_t triangle,
                                         int32_t offset,
                                         uint32_t scaleMilli) {
    const uint8_t* tri = indices + ((size_t)triangle * 12u);
    uint32_t i1 = OrenAVMGfxResourceReadU32LE(tri);
    uint32_t i2 = OrenAVMGfxResourceReadU32LE(tri + 4);
    uint32_t i3 = OrenAVMGfxResourceReadU32LE(tri + 8);
    int64_t z = (int64_t)(int32_t)OrenAVMGfxResourceReadU32LE(vertices + ((size_t)i1 * 12u) + 8) +
        (int64_t)(int32_t)OrenAVMGfxResourceReadU32LE(vertices + ((size_t)i2 * 12u) + 8) +
        (int64_t)(int32_t)OrenAVMGfxResourceReadU32LE(vertices + ((size_t)i3 * 12u) + 8);
    return (z * (int64_t)scaleMilli) / 1000 + (int64_t)offset * 3;
}

CGFloat OrenAVMGfxMesh3DModelCoord(const uint8_t* p, int32_t offset, uint32_t scaleMilli) {
    int32_t v = (int32_t)OrenAVMGfxResourceReadU32LE(p);
    return (CGFloat)(((int64_t)v * (int64_t)scaleMilli) / 1000 + (int64_t)offset);
}

#endif
