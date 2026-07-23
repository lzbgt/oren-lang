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

static BOOL OrenAVMGfxEnsureRetainedResourceMap(CFMutableDictionaryRef* map);
static BOOL OrenAVMGfxEnsureScalarResourceMap(CFMutableDictionaryRef* map);

uint8_t* OrenAVMGfxCopyPayloadBytes(const uint8_t* src, NSUInteger len) {
    if (!src || len == 0) return NULL;
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
                                const uint8_t* rgba,
                                uint32_t imageID,
                                uint32_t width,
                                uint32_t height,
                                uint32_t byteCount,
                                NSUInteger retainedImageCountLimit,
                                NSUInteger retainedImagePixelLimit,
                                NSUInteger* retainedImagePixelCount) {
    if (!imagesByID || !rgba || imageID == 0 || width == 0 || height == 0 || !retainedImagePixelCount) return NO;
    uint64_t expected = (uint64_t)width * (uint64_t)height * 4ull;
    if (expected != (uint64_t)byteCount) return NO;
    uint64_t pixel64 = (uint64_t)width * (uint64_t)height;
    if (pixel64 > (uint64_t)NSUIntegerMax) return NO;
    NSUInteger pixels = (NSUInteger)pixel64;
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
    if (!*imagesByID) *imagesByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!*imagesByID) return NO;
    UIImage* image = OrenAVMGfxImageRGBA(rgba, width, height, byteCount);
    if (!image) return NO;
    OrenAVMGfxImageResource* resource = [[OrenAVMGfxImageResource alloc] init];
    resource.image = image;
    resource.pixels = pixels;
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
    return sw > 0 && sh > 0 &&
        (uint64_t)sx + (uint64_t)sw <= (uint64_t)width &&
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
    if (!cgImage || w == 0 || h == 0 || !OrenAVMGfxSubrectInImage(sx, sy, sw, sh, imageWidth, imageHeight)) return;
    CGImageRef subImage = CGImageCreateWithImageInRect(cgImage, CGRectMake((CGFloat)sx, (CGFloat)sy, (CGFloat)sw, (CGFloat)sh));
    if (!subImage) return;
    UIImage* cropped = [UIImage imageWithCGImage:subImage];
    [cropped drawInRect:CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h)];
    CGImageRelease(subImage);
}

BOOL OrenAVMGfxHandleImageCommand(CGContextRef ctx,
                                  CFMutableDictionaryRef* images,
                                  NSUInteger retainedImageCountLimit,
                                  NSUInteger retainedImagePixelLimit,
                                  NSUInteger* retainedImagePixelCount,
                                  uint8_t opcode,
                                  const uint8_t* payload,
                                  uint16_t payloadLen) {
    if (!ctx || !payload) return NO;
    switch (opcode) {
        case 64: {
            if (payloadLen >= 16) {
                uint32_t imageID = OrenAVMGfxResourceReadU32LE(payload);
                uint32_t iw = OrenAVMGfxResourceReadU32LE(payload + 4);
                uint32_t ih = OrenAVMGfxResourceReadU32LE(payload + 8);
                uint32_t imageLen = OrenAVMGfxResourceReadU32LE(payload + 12);
                if (imageLen == (uint32_t)payloadLen - 16u) {
                    (void)OrenAVMGfxPutImageResource(images,
                                                     payload + 16,
                                                     imageID,
                                                     iw,
                                                     ih,
                                                     imageLen,
                                                     retainedImageCountLimit,
                                                     retainedImagePixelLimit,
                                                     retainedImagePixelCount);
                }
            }
            return YES;
        }
        case 65: {
            if (payloadLen == 20) {
                uint32_t imageID = OrenAVMGfxResourceReadU32LE(payload);
                uint32_t x = OrenAVMGfxResourceReadU32LE(payload + 4);
                uint32_t y = OrenAVMGfxResourceReadU32LE(payload + 8);
                uint32_t w = OrenAVMGfxResourceReadU32LE(payload + 12);
                uint32_t h = OrenAVMGfxResourceReadU32LE(payload + 16);
                UIImage* image = OrenAVMGfxRetainedImageResource(images ? *images : NULL, imageID).image;
                if (image) [image drawInRect:CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h)];
            }
            return YES;
        }
        case 66:
            if (payloadLen == 4) OrenAVMGfxRemoveImageResource(images ? *images : NULL, OrenAVMGfxResourceReadU32LE(payload), retainedImagePixelCount);
            return YES;
        case 67: {
            if (payloadLen == 36) {
                uint32_t imageID = OrenAVMGfxResourceReadU32LE(payload);
                uint32_t sx = OrenAVMGfxResourceReadU32LE(payload + 4);
                uint32_t sy = OrenAVMGfxResourceReadU32LE(payload + 8);
                uint32_t sw = OrenAVMGfxResourceReadU32LE(payload + 12);
                uint32_t sh = OrenAVMGfxResourceReadU32LE(payload + 16);
                uint32_t x = OrenAVMGfxResourceReadU32LE(payload + 20);
                uint32_t y = OrenAVMGfxResourceReadU32LE(payload + 24);
                uint32_t w = OrenAVMGfxResourceReadU32LE(payload + 28);
                uint32_t h = OrenAVMGfxResourceReadU32LE(payload + 32);
                UIImage* image = OrenAVMGfxRetainedImageResource(images ? *images : NULL, imageID).image;
                CGImageRef cgImage = image.CGImage;
                if (cgImage) {
                    OrenAVMGfxDrawImageSubrect(cgImage, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage),
                                               sx, sy, sw, sh, x, y, w, h);
                }
            }
            return YES;
        }
        case 71: {
            if (payloadLen >= 40 && ((payloadLen - 8) % 32) == 0) {
                uint32_t imageID = OrenAVMGfxResourceReadU32LE(payload);
                uint32_t rectCount = OrenAVMGfxResourceReadU32LE(payload + 4);
                UIImage* image = OrenAVMGfxRetainedImageResource(images ? *images : NULL, imageID).image;
                CGImageRef cgImage = image.CGImage;
                if (cgImage && rectCount == ((uint32_t)payloadLen - 8u) / 32u) {
                    size_t imageWidth = CGImageGetWidth(cgImage);
                    size_t imageHeight = CGImageGetHeight(cgImage);
                    for (uint32_t ri = 0; ri < rectCount; ri++) {
                        const uint8_t* r = payload + 8 + ((size_t)ri * 32u);
                        uint32_t sx = OrenAVMGfxResourceReadU32LE(r);
                        uint32_t sy = OrenAVMGfxResourceReadU32LE(r + 4);
                        uint32_t sw = OrenAVMGfxResourceReadU32LE(r + 8);
                        uint32_t sh = OrenAVMGfxResourceReadU32LE(r + 12);
                        uint32_t x = OrenAVMGfxResourceReadU32LE(r + 16);
                        uint32_t y = OrenAVMGfxResourceReadU32LE(r + 20);
                        uint32_t w = OrenAVMGfxResourceReadU32LE(r + 24);
                        uint32_t h = OrenAVMGfxResourceReadU32LE(r + 28);
                        OrenAVMGfxDrawImageSubrect(cgImage, imageWidth, imageHeight, sx, sy, sw, sh, x, y, w, h);
                    }
                }
            }
            return YES;
        }
        default:
            return NO;
    }
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
    if (!OrenAVMGfxEnsureRetainedResourceMap(texts)) return NO;
    NSString* text = [[NSString alloc] initWithBytes:textBytes length:(NSUInteger)textLen encoding:NSUTF8StringEncoding];
    if (!text) return NO;
    OrenAVMGfxTextResource* resource = [[OrenAVMGfxTextResource alloc] init];
    resource.attributedText = [[NSAttributedString alloc] initWithString:text attributes:attrs];
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

BOOL OrenAVMGfxHandleTextCommand(CGContextRef ctx,
                                 CFMutableDictionaryRef* attrsByRGBA,
                                 uint32_t* lastRGBA,
                                 NSDictionary<NSAttributedStringKey, id>* __strong* lastAttributes,
                                 CFMutableDictionaryRef* texts,
                                 uint8_t opcode,
                                 const uint8_t* payload,
                                 uint16_t payloadLen) {
    if (!ctx || !payload) return NO;
    switch (opcode) {
        case 2: {
            if (payloadLen >= 16) {
                uint32_t x = OrenAVMGfxResourceReadU32LE(payload);
                uint32_t y = OrenAVMGfxResourceReadU32LE(payload + 4);
                uint32_t textLen = OrenAVMGfxResourceReadU32LE(payload + 12);
                if (textLen <= (uint32_t)payloadLen - 16u) {
                    NSDictionary<NSAttributedStringKey, id>* attrs = OrenAVMGfxTextAttributesForRGBA(attrsByRGBA,
                                                                                                      lastRGBA,
                                                                                                      lastAttributes,
                                                                                                      OrenAVMGfxResourceReadU32LE(payload + 8));
                    OrenAVMGfxDrawTextBytes(payload + 16, textLen, x, y, attrs);
                }
            }
            return YES;
        }
        case 68: {
            if (payloadLen >= 12) {
                uint32_t textID = OrenAVMGfxResourceReadU32LE(payload);
                uint32_t textLen = OrenAVMGfxResourceReadU32LE(payload + 8);
                if (textLen == (uint32_t)payloadLen - 12u) {
                    NSDictionary<NSAttributedStringKey, id>* attrs = OrenAVMGfxTextAttributesForRGBA(attrsByRGBA,
                                                                                                      lastRGBA,
                                                                                                      lastAttributes,
                                                                                                      OrenAVMGfxResourceReadU32LE(payload + 4));
                    (void)OrenAVMGfxPutTextResource(texts, textID, payload + 12, textLen, attrs);
                }
            }
            return YES;
        }
        case 69:
            if (payloadLen == 12) {
                uint32_t textID = OrenAVMGfxResourceReadU32LE(payload);
                uint32_t x = OrenAVMGfxResourceReadU32LE(payload + 4);
                uint32_t y = OrenAVMGfxResourceReadU32LE(payload + 8);
                OrenAVMGfxDrawTextResource(texts ? *texts : NULL, textID, x, y);
            }
            return YES;
        case 70:
            if (payloadLen == 4) OrenAVMGfxRemoveTextResource(texts ? *texts : NULL, OrenAVMGfxResourceReadU32LE(payload));
            return YES;
        case 72: {
            if (payloadLen >= 16 && ((payloadLen - 8) % 8) == 0) {
                uint32_t textID = OrenAVMGfxResourceReadU32LE(payload);
                uint32_t posCount = OrenAVMGfxResourceReadU32LE(payload + 4);
                if (posCount == ((uint32_t)payloadLen - 8u) / 8u) {
                    OrenAVMGfxDrawTextResourcePositions(texts ? *texts : NULL, textID, payload + 8, posCount);
                }
            }
            return YES;
        }
        default:
            return NO;
    }
}

const void* OrenAVMGfxRetainedMeshKey(uint32_t meshID) {
    return OrenAVMGfxRetainedKey(meshID);
}

OrenAVMGfxMeshResource* OrenAVMGfxRetainedMeshResource(CFDictionaryRef meshes, uint32_t meshID) {
    if (!meshes || meshID == 0) return nil;
    return (__bridge OrenAVMGfxMeshResource*)CFDictionaryGetValue(meshes, OrenAVMGfxRetainedMeshKey(meshID));
}

static BOOL OrenAVMGfxTriangleOrderAppend(OrenAVMGfxTriangleOrder** order,
                                          OrenAVMGfxTriangleOrder* inlineOrder,
                                          uint32_t* capacity,
                                          OrenAVMGfxTriangleOrder** heapStorage,
                                          uint32_t* count,
                                          uint32_t triangle,
                                          int64_t zsum);

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
    if (!OrenAVMGfxEnsureRetainedResourceMap(meshes)) return NO;
    uint8_t* triangleCopy = OrenAVMGfxCopyPayloadBytes(triangles, triangleBytes);
    if (!triangleCopy) return NO;
    OrenAVMGfxMeshResource* mesh = [[OrenAVMGfxMeshResource alloc] init];
    if (!mesh) {
        free(triangleCopy);
        return NO;
    }
    mesh.rgbaValue = rgbaValue;
    mesh.triangleBytes = triangleBytes;
    mesh.triangles = triangleCopy;
    mesh.triangleCount = triangleCount;
    mesh.stride = stride;
    mesh.hasRGBA = hasRGBA;
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
    if (!OrenAVMGfxEnsureRetainedResourceMap(meshes)) return NO;
    uint8_t* vertexCopy = OrenAVMGfxCopyPayloadBytes(vertices, vertexBytes);
    if (!vertexCopy) return NO;
    uint8_t* indexCopy = OrenAVMGfxCopyPayloadBytes(indices, indexBytes);
    if (!indexCopy) {
        free(vertexCopy);
        return NO;
    }
    OrenAVMGfxMeshResource* mesh = [[OrenAVMGfxMeshResource alloc] init];
    if (!mesh) {
        free(vertexCopy);
        free(indexCopy);
        return NO;
    }
    mesh.rgbaValue = rgbaValue;
    mesh.vertexBytes = vertexBytes;
    mesh.indexBytes = indexBytes;
    mesh.vertices = vertexCopy;
    mesh.indices = indexCopy;
    mesh.triangleCount = indexCount / 3u;
    mesh.indexCount = indexCount;
    CFDictionarySetValue(*meshes, OrenAVMGfxRetainedMeshKey(meshID), (__bridge const void*)mesh);
    return YES;
}

void OrenAVMGfxRemoveMeshResource(CFMutableDictionaryRef meshes, uint32_t meshID) {
    if (meshes && meshID != 0) CFDictionaryRemoveValue(meshes, OrenAVMGfxRetainedMeshKey(meshID));
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

static BOOL OrenAVMGfxTriangleIsDegenerate(CGFloat x1,
                                           CGFloat y1,
                                           CGFloat x2,
                                           CGFloat y2,
                                           CGFloat x3,
                                           CGFloat y3) {
    CGFloat area2 = (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1);
    return area2 == 0.0;
}

void OrenAVMGfxDrawMesh2DResource(CGContextRef ctx, CFDictionaryRef meshes, uint32_t meshID) {
    OrenAVMGfxMeshResource* mesh = OrenAVMGfxRetainedMeshResource(meshes, meshID);
    const uint8_t* tris = mesh.triangles;
    if (!ctx || !tris || mesh.triangleCount != mesh.triangleBytes / 24u) return;
    OrenAVMGfxSetFillColorValue(ctx, mesh.rgbaValue);
    for (uint32_t ti = 0; ti < mesh.triangleCount; ti++) {
        const uint8_t* tri = tris + ((size_t)ti * 24u);
        CGFloat x1 = (CGFloat)OrenAVMGfxResourceReadU32LE(tri);
        CGFloat y1 = (CGFloat)OrenAVMGfxResourceReadU32LE(tri + 4);
        CGFloat x2 = (CGFloat)OrenAVMGfxResourceReadU32LE(tri + 8);
        CGFloat y2 = (CGFloat)OrenAVMGfxResourceReadU32LE(tri + 12);
        CGFloat x3 = (CGFloat)OrenAVMGfxResourceReadU32LE(tri + 16);
        CGFloat y3 = (CGFloat)OrenAVMGfxResourceReadU32LE(tri + 20);
        if (OrenAVMGfxTriangleIsDegenerate(x1, y1, x2, y2, x3, y3)) continue;
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, x1, y1);
        CGContextAddLineToPoint(ctx, x2, y2);
        CGContextAddLineToPoint(ctx, x3, y3);
        CGContextClosePath(ctx);
        CGContextFillPath(ctx);
    }
}

void OrenAVMGfxDrawMesh3DResource(CGContextRef ctx,
                                  CFDictionaryRef meshes,
                                  CFDictionaryRef materials,
                                  CFDictionaryRef models,
                                  uint8_t opcode,
                                  const uint8_t* payload,
                                  BOOL depthEnabled,
                                  int32_t nearZ,
                                  int32_t farZ) {
    if (!ctx || !payload) return;
    uint32_t meshID = OrenAVMGfxResourceReadU32LE(payload);
    uint32_t materialID = 0;
    int32_t modelX = 0;
    int32_t modelY = 0;
    int32_t modelZ = 0;
    uint32_t scaleMilli = 1000u;
    if (opcode == 94) {
        OrenAVMGfxModelResource* model = OrenAVMGfxRetainedModelResource(models, meshID);
        if (!model) return;
        meshID = model.meshID;
        materialID = model.materialID;
        modelX = model.x;
        modelY = model.y;
        modelZ = model.z;
        scaleMilli = model.scaleMilli;
    }
    OrenAVMGfxMeshResource* mesh = OrenAVMGfxRetainedMeshResource(meshes, meshID);
    BOOL hasMaterialRGBA = NO;
    uint32_t materialRGBAOverride = 0;
    if (opcode == 90 || opcode == 91) materialID = OrenAVMGfxResourceReadU32LE(payload + 4);
    if (materialID != 0) {
        hasMaterialRGBA = OrenAVMGfxRetainedMaterialRGBA(materials, materialID, &materialRGBAOverride);
        if (!hasMaterialRGBA) return;
    }
    const uint8_t* tris = mesh.triangles;
    const uint8_t* verts = mesh.vertices;
    const uint8_t* idx = mesh.indices;
    uint32_t meshStride = mesh.stride;
    uint32_t triangleCount = mesh.triangleCount;
    uint32_t rgbaValue = hasMaterialRGBA ? materialRGBAOverride : mesh.rgbaValue;
    if (opcode == 87) {
        modelX = (int32_t)OrenAVMGfxResourceReadU32LE(payload + 4);
        modelY = (int32_t)OrenAVMGfxResourceReadU32LE(payload + 8);
        modelZ = (int32_t)OrenAVMGfxResourceReadU32LE(payload + 12);
        scaleMilli = OrenAVMGfxResourceReadU32LE(payload + 16);
    } else if (opcode == 91) {
        modelX = (int32_t)OrenAVMGfxResourceReadU32LE(payload + 8);
        modelY = (int32_t)OrenAVMGfxResourceReadU32LE(payload + 12);
        modelZ = (int32_t)OrenAVMGfxResourceReadU32LE(payload + 16);
        scaleMilli = OrenAVMGfxResourceReadU32LE(payload + 20);
    }
    if (verts && idx && scaleMilli != 0 && triangleCount == mesh.indexBytes / 12u && mesh.vertexBytes % 12u == 0) {
        OrenAVMGfxTriangleOrder inlineOrder[OrenAVMGfxInlineTriangleOrderCapacity];
        OrenAVMGfxTriangleOrder* order = inlineOrder;
        OrenAVMGfxTriangleOrder* heapOrder = NULL;
        uint32_t orderCapacity = OrenAVMGfxInlineTriangleOrderCapacity;
        uint32_t visibleCount = 0;
        for (uint32_t ti = 0; ti < triangleCount; ti++) {
            int64_t z = OrenAVMGfxMesh3DIndexedZSumModel(verts, idx, ti, modelZ, scaleMilli);
            if (!OrenAVMGfxMesh3DZVisible(z, depthEnabled, nearZ, farZ)) continue;
            if (!OrenAVMGfxTriangleOrderAppend(&order, inlineOrder, &orderCapacity, &heapOrder, &visibleCount, ti, z)) {
                free(heapOrder);
                return;
            }
        }
        OrenAVMGfxSortTriangleOrder(order, visibleCount);
        OrenAVMGfxSetFillColorValue(ctx, rgbaValue);
        for (uint32_t oi = 0; oi < visibleCount; oi++) {
            const uint8_t* tri = idx + ((size_t)order[oi].triangle * 12u);
            const uint8_t* v1 = verts + ((size_t)OrenAVMGfxResourceReadU32LE(tri) * 12u);
            const uint8_t* v2 = verts + ((size_t)OrenAVMGfxResourceReadU32LE(tri + 4) * 12u);
            const uint8_t* v3 = verts + ((size_t)OrenAVMGfxResourceReadU32LE(tri + 8) * 12u);
            CGFloat x1 = OrenAVMGfxMesh3DModelCoord(v1, modelX, scaleMilli);
            CGFloat y1 = OrenAVMGfxMesh3DModelCoord(v1 + 4, modelY, scaleMilli);
            CGFloat x2 = OrenAVMGfxMesh3DModelCoord(v2, modelX, scaleMilli);
            CGFloat y2 = OrenAVMGfxMesh3DModelCoord(v2 + 4, modelY, scaleMilli);
            CGFloat x3 = OrenAVMGfxMesh3DModelCoord(v3, modelX, scaleMilli);
            CGFloat y3 = OrenAVMGfxMesh3DModelCoord(v3 + 4, modelY, scaleMilli);
            if (OrenAVMGfxTriangleIsDegenerate(x1, y1, x2, y2, x3, y3)) continue;
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, x1, y1);
            CGContextAddLineToPoint(ctx, x2, y2);
            CGContextAddLineToPoint(ctx, x3, y3);
            CGContextClosePath(ctx);
            CGContextFillPath(ctx);
        }
        free(heapOrder);
    } else if (tris && scaleMilli != 0 && (meshStride == 36u || meshStride == 40u) && triangleCount == mesh.triangleBytes / meshStride) {
        OrenAVMGfxTriangleOrder inlineOrder[OrenAVMGfxInlineTriangleOrderCapacity];
        OrenAVMGfxTriangleOrder* order = inlineOrder;
        OrenAVMGfxTriangleOrder* heapOrder = NULL;
        uint32_t orderCapacity = OrenAVMGfxInlineTriangleOrderCapacity;
        uint32_t visibleCount = 0;
        for (uint32_t ti = 0; ti < triangleCount; ti++) {
            int64_t z = OrenAVMGfxMesh3DZSumModel(tris + ((size_t)ti * meshStride), modelZ, scaleMilli);
            if (!OrenAVMGfxMesh3DZVisible(z, depthEnabled, nearZ, farZ)) continue;
            if (!OrenAVMGfxTriangleOrderAppend(&order, inlineOrder, &orderCapacity, &heapOrder, &visibleCount, ti, z)) {
                free(heapOrder);
                return;
            }
        }
        OrenAVMGfxSortTriangleOrder(order, visibleCount);
        if (hasMaterialRGBA || !mesh.hasRGBA) OrenAVMGfxSetFillColorValue(ctx, rgbaValue);
        for (uint32_t oi = 0; oi < visibleCount; oi++) {
            const uint8_t* tri = tris + ((size_t)order[oi].triangle * meshStride);
            if (!hasMaterialRGBA && mesh.hasRGBA) OrenAVMGfxSetFillColorBytes(ctx, tri + 36);
            CGFloat x1 = OrenAVMGfxMesh3DModelCoord(tri, modelX, scaleMilli);
            CGFloat y1 = OrenAVMGfxMesh3DModelCoord(tri + 4, modelY, scaleMilli);
            CGFloat x2 = OrenAVMGfxMesh3DModelCoord(tri + 12, modelX, scaleMilli);
            CGFloat y2 = OrenAVMGfxMesh3DModelCoord(tri + 16, modelY, scaleMilli);
            CGFloat x3 = OrenAVMGfxMesh3DModelCoord(tri + 24, modelX, scaleMilli);
            CGFloat y3 = OrenAVMGfxMesh3DModelCoord(tri + 28, modelY, scaleMilli);
            if (OrenAVMGfxTriangleIsDegenerate(x1, y1, x2, y2, x3, y3)) continue;
            CGContextBeginPath(ctx);
            CGContextMoveToPoint(ctx, x1, y1);
            CGContextAddLineToPoint(ctx, x2, y2);
            CGContextAddLineToPoint(ctx, x3, y3);
            CGContextClosePath(ctx);
            CGContextFillPath(ctx);
        }
        free(heapOrder);
    }
}

BOOL OrenAVMGfxHandleMeshCommand(CGContextRef ctx,
                                 CFMutableDictionaryRef* meshes,
                                 CFMutableDictionaryRef* materials,
                                 CFMutableDictionaryRef* models,
                                 uint8_t opcode,
                                 const uint8_t* payload,
                                 uint16_t payloadLen,
                                 BOOL depthEnabled,
                                 int32_t nearZ,
                                 int32_t farZ) {
    if (!ctx || !payload) return NO;
    switch (opcode) {
        case 80: {
            if (payloadLen >= 36 && ((payloadLen - 12) % 24) == 0) {
                uint32_t meshID = OrenAVMGfxResourceReadU32LE(payload);
                uint32_t triangleCount = OrenAVMGfxResourceReadU32LE(payload + 8);
                if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 12u) / 24u) {
                    (void)OrenAVMGfxPutTriangleMeshResource(meshes,
                                                            meshID,
                                                            OrenAVMGfxResourceReadU32LE(payload + 4),
                                                            payload + 12,
                                                            (NSUInteger)payloadLen - 12u,
                                                            triangleCount,
                                                            24u,
                                                            NO);
                }
            }
            return YES;
        }
        case 81:
            if (payloadLen == 4) OrenAVMGfxDrawMesh2DResource(ctx, meshes ? *meshes : NULL, OrenAVMGfxResourceReadU32LE(payload));
            return YES;
        case 82:
            if (payloadLen == 4) OrenAVMGfxRemoveMeshResource(meshes ? *meshes : NULL, OrenAVMGfxResourceReadU32LE(payload));
            return YES;
        case 83: {
            if (payloadLen >= 48 && ((payloadLen - 12) % 36) == 0) {
                uint32_t meshID = OrenAVMGfxResourceReadU32LE(payload);
                uint32_t triangleCount = OrenAVMGfxResourceReadU32LE(payload + 8);
                if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 12u) / 36u) {
                    (void)OrenAVMGfxPutTriangleMeshResource(meshes,
                                                            meshID,
                                                            OrenAVMGfxResourceReadU32LE(payload + 4),
                                                            payload + 12,
                                                            (NSUInteger)payloadLen - 12u,
                                                            triangleCount,
                                                            36u,
                                                            NO);
                }
            }
            return YES;
        }
        case 84:
        case 87:
        case 90:
        case 91:
        case 94:
            if ((opcode == 84 && payloadLen == 4) || (opcode == 87 && payloadLen == 20) ||
                (opcode == 90 && payloadLen == 8) || (opcode == 91 && payloadLen == 24) ||
                (opcode == 94 && payloadLen == 4)) {
                OrenAVMGfxDrawMesh3DResource(ctx,
                                             meshes ? *meshes : NULL,
                                             materials ? *materials : NULL,
                                             models ? *models : NULL,
                                             opcode,
                                             payload,
                                             depthEnabled,
                                             nearZ,
                                             farZ);
            }
            return YES;
        case 85:
            if (payloadLen == 4) OrenAVMGfxRemoveMeshResource(meshes ? *meshes : NULL, OrenAVMGfxResourceReadU32LE(payload));
            return YES;
        case 86: {
            if (payloadLen >= 48 && ((payloadLen - 8) % 40) == 0) {
                uint32_t meshID = OrenAVMGfxResourceReadU32LE(payload);
                uint32_t triangleCount = OrenAVMGfxResourceReadU32LE(payload + 4);
                if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 8u) / 40u) {
                    (void)OrenAVMGfxPutTriangleMeshResource(meshes,
                                                            meshID,
                                                            0,
                                                            payload + 8,
                                                            (NSUInteger)payloadLen - 8u,
                                                            triangleCount,
                                                            40u,
                                                            YES);
                }
            }
            return YES;
        }
        case 88: {
            if (payloadLen >= 64) {
                uint32_t meshID = OrenAVMGfxResourceReadU32LE(payload);
                uint32_t vertexCount = OrenAVMGfxResourceReadU32LE(payload + 8);
                uint32_t indexCount = OrenAVMGfxResourceReadU32LE(payload + 12);
                size_t vertexBytes = (size_t)vertexCount * 12u;
                size_t indexBytes = (size_t)indexCount * 4u;
                if (16u + vertexBytes + indexBytes == (size_t)payloadLen) {
                    (void)OrenAVMGfxPutIndexedMeshResource(meshes,
                                                           meshID,
                                                           OrenAVMGfxResourceReadU32LE(payload + 4),
                                                           payload + 16,
                                                           vertexBytes,
                                                           vertexCount,
                                                           payload + 16 + vertexBytes,
                                                           indexBytes,
                                                           indexCount);
                }
            }
            return YES;
        }
        case 89:
            if (payloadLen == 8) {
                uint32_t materialID = OrenAVMGfxResourceReadU32LE(payload);
                (void)OrenAVMGfxPutMaterialResource(materials, materialID, OrenAVMGfxResourceReadU32LE(payload + 4));
            }
            return YES;
        case 92:
            if (payloadLen == 4) OrenAVMGfxRemoveMaterialResource(materials ? *materials : NULL, OrenAVMGfxResourceReadU32LE(payload));
            return YES;
        case 93:
            if (payloadLen == 28) {
                uint32_t modelID = OrenAVMGfxResourceReadU32LE(payload);
                uint32_t meshID = OrenAVMGfxResourceReadU32LE(payload + 4);
                uint32_t scaleMilli = OrenAVMGfxResourceReadU32LE(payload + 24);
                (void)OrenAVMGfxPutModelResource(models,
                                                 modelID,
                                                 meshID,
                                                 OrenAVMGfxResourceReadU32LE(payload + 8),
                                                 (int32_t)OrenAVMGfxResourceReadU32LE(payload + 12),
                                                 (int32_t)OrenAVMGfxResourceReadU32LE(payload + 16),
                                                 (int32_t)OrenAVMGfxResourceReadU32LE(payload + 20),
                                                 scaleMilli);
            }
            return YES;
        case 95:
            if (payloadLen == 4) OrenAVMGfxRemoveModelResource(models ? *models : NULL, OrenAVMGfxResourceReadU32LE(payload));
            return YES;
        default:
            return NO;
    }
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
    if (!OrenAVMGfxEnsureRetainedResourceMap(models)) return NO;
    OrenAVMGfxModelResource* model = [[OrenAVMGfxModelResource alloc] init];
    model.meshID = meshID;
    model.materialID = materialID;
    model.x = x;
    model.y = y;
    model.z = z;
    model.scaleMilli = scaleMilli;
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

void OrenAVMGfxSortTriangleOrder(OrenAVMGfxTriangleOrder* order, uint32_t count) {
    if (count > 1) qsort(order, count, sizeof(OrenAVMGfxTriangleOrder), OrenAVMGfxTriangleOrderCompare);
}

static BOOL OrenAVMGfxTriangleOrderAppend(OrenAVMGfxTriangleOrder** order,
                                          OrenAVMGfxTriangleOrder* inlineOrder,
                                          uint32_t* capacity,
                                          OrenAVMGfxTriangleOrder** heapStorage,
                                          uint32_t* count,
                                          uint32_t triangle,
                                          int64_t zsum) {
    if (!order || !*order || !capacity || !heapStorage || !count || *count == UINT32_MAX) return NO;
    if (*count >= *capacity) {
        uint32_t oldCapacity = *capacity;
        uint32_t needed = *count + 1u;
        uint32_t newCapacity = oldCapacity > 0 ? oldCapacity : 1u;
        while (newCapacity < needed) {
            if (newCapacity > UINT32_MAX / 2u) {
                newCapacity = needed;
                break;
            }
            newCapacity *= 2u;
        }
        if ((NSUInteger)newCapacity > NSUIntegerMax / sizeof(OrenAVMGfxTriangleOrder)) return NO;
        OrenAVMGfxTriangleOrder* grown = NULL;
        if (*heapStorage) {
            grown = (OrenAVMGfxTriangleOrder*)realloc(*heapStorage, (NSUInteger)newCapacity * sizeof(OrenAVMGfxTriangleOrder));
        } else {
            grown = (OrenAVMGfxTriangleOrder*)malloc((NSUInteger)newCapacity * sizeof(OrenAVMGfxTriangleOrder));
            if (grown && inlineOrder && *count != 0) {
                memcpy(grown, inlineOrder, (NSUInteger)*count * sizeof(OrenAVMGfxTriangleOrder));
            }
        }
        if (!grown) return NO;
        *heapStorage = grown;
        *order = grown;
        *capacity = newCapacity;
    }
    (*order)[*count] = (OrenAVMGfxTriangleOrder){triangle, zsum};
    *count += 1u;
    return YES;
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
