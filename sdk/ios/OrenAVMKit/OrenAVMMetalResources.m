#import "OrenAVMMetalResources.h"
#import "OrenAVMMetalFrame.h"

#if TARGET_OS_IPHONE

#include <stdlib.h>
#include <string.h>

@implementation OrenAVMMetalVertexRun
- (void)dealloc {
    free(_vertices);
}
@end

@implementation OrenAVMMetalImageRun
- (void)dealloc {
    free(heapVertices);
}
@end

@implementation OrenAVMMetalImageResource
@end

@implementation OrenAVMMetalMesh2DResource
- (void)dealloc {
    free(_triangles);
}
@end

@implementation OrenAVMMetalMesh3DResource
- (void)dealloc {
    free(_triangles);
    free(_vertices);
    free(_indices);
}
@end

@implementation OrenAVMMetalModelResource
@end

static const void* OrenAVMMetalRetainedKey(uint32_t idValue) {
    return (const void*)(uintptr_t)((uint64_t)idValue + 1ull);
}

static BOOL OrenAVMMetalEnsureRetainedResourceMap(CFMutableDictionaryRef* map) {
    if (!map) return NO;
    if (!*map) *map = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    return *map != NULL;
}

static BOOL OrenAVMMetalEnsureScalarResourceMap(CFMutableDictionaryRef* map) {
    if (!map) return NO;
    if (!*map) *map = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    return *map != NULL;
}

const void* OrenAVMMetalRetainedImageKey(uint32_t imageID) {
    return OrenAVMMetalRetainedKey(imageID);
}

OrenAVMMetalImageResource* OrenAVMMetalRetainedImageResource(CFDictionaryRef images, uint32_t imageID) {
    if (!images || imageID == 0) return nil;
    return (__bridge OrenAVMMetalImageResource*)CFDictionaryGetValue(images, OrenAVMMetalRetainedImageKey(imageID));
}

BOOL OrenAVMMetalPutImageResource(CFMutableDictionaryRef* imagesByID,
                                  id<MTLDevice> device,
                                  uint32_t imageID,
                                  uint32_t width,
                                  uint32_t height,
                                  const uint8_t* rgba,
                                  uint32_t byteCount,
                                  NSUInteger retainedImageCountLimit,
                                  NSUInteger retainedImagePixelLimit,
                                  NSUInteger* retainedImagePixelCount) {
    if (!imagesByID || !device || imageID == 0 || width == 0 || height == 0 || !rgba || !retainedImagePixelCount) return NO;
    uint64_t expected = (uint64_t)width * (uint64_t)height * 4ull;
    if (expected != (uint64_t)byteCount) return NO;
    NSUInteger pixels = (NSUInteger)width * (NSUInteger)height;
    OrenAVMMetalImageResource* oldResource = OrenAVMMetalRetainedImageResource(*imagesByID, imageID);
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

    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                          width:(NSUInteger)width
                                                                                         height:(NSUInteger)height
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
    if (!texture) return NO;
    [texture replaceRegion:MTLRegionMake2D(0, 0, (NSUInteger)width, (NSUInteger)height)
               mipmapLevel:0
                 withBytes:rgba
               bytesPerRow:(NSUInteger)width * 4u];

    OrenAVMMetalImageResource* resource = [[OrenAVMMetalImageResource alloc] init];
    if (!resource) return NO;
    resource.texture = texture;
    resource.pixels = pixels;
    CFDictionarySetValue(*imagesByID, OrenAVMMetalRetainedImageKey(imageID), (__bridge const void*)resource);
    *retainedImagePixelCount = pixelAfter;
    return YES;
}

void OrenAVMMetalRemoveImageResource(CFMutableDictionaryRef imagesByID,
                                     uint32_t imageID,
                                     NSUInteger* retainedImagePixelCount) {
    if (imageID == 0 || !imagesByID) return;
    OrenAVMMetalImageResource* old = OrenAVMMetalRetainedImageResource(imagesByID, imageID);
    if (old && retainedImagePixelCount) {
        NSUInteger pixels = old.pixels;
        *retainedImagePixelCount = *retainedImagePixelCount > pixels ? *retainedImagePixelCount - pixels : 0;
    }
    CFDictionaryRemoveValue(imagesByID, OrenAVMMetalRetainedImageKey(imageID));
}

OrenAVMMetalImageRun* OrenAVMMetalImageRunCreate(id<MTLTexture> texture,
                                                 NSUInteger textureWidth,
                                                 NSUInteger textureHeight,
                                                 uint32_t sx,
                                                 uint32_t sy,
                                                 uint32_t sw,
                                                 uint32_t sh,
                                                 float x,
                                                 float y,
                                                 float w,
                                                 float h,
                                                 float opacity,
                                                 float logicalWidth,
                                                 float logicalHeight) {
    if (!texture || w <= 0.0f || h <= 0.0f || sw == 0 || sh == 0) return nil;
    if (!OrenAVMMetalSubrectInTexture(sx, sy, sw, sh, textureWidth, textureHeight)) return nil;
    float u0 = (float)sx / (float)textureWidth;
    float v0 = (float)sy / (float)textureHeight;
    float u1 = (float)((uint64_t)sx + (uint64_t)sw) / (float)textureWidth;
    float v1 = (float)((uint64_t)sy + (uint64_t)sh) / (float)textureHeight;
    OrenAVMMetalImageRun* run = [[OrenAVMMetalImageRun alloc] init];
    if (!run) return nil;
    run.texture = texture;
    OrenAVMMetalWriteTextureQuad(run->vertices, x, y, w, h, logicalWidth, logicalHeight, u0, v0, u1, v1);
    run->inlineVertexCount = 6u;
    run.opacity = opacity;
    return run;
}

static BOOL OrenAVMMetalImageRectsHaveZeroSize(const uint8_t* rects, uint32_t rectCount) {
    if (!rects) return YES;
    for (uint32_t ri = 0; ri < rectCount; ri++) {
        const uint8_t* r = rects + ((size_t)ri * 32u);
        if (OrenAVMMetalReadU32LE(r + 8) == 0 ||
            OrenAVMMetalReadU32LE(r + 12) == 0 ||
            OrenAVMMetalReadU32LE(r + 24) == 0 ||
            OrenAVMMetalReadU32LE(r + 28) == 0) {
            return YES;
        }
    }
    return NO;
}

static BOOL OrenAVMMetalImageRunReserveHeapVertices(OrenAVMMetalImageRun* run, NSUInteger neededCount) {
    if (!run || neededCount == 0 || neededCount > NSUIntegerMax / sizeof(OrenAVMMetalTextVertex)) return NO;
    if (neededCount <= run->heapVertexCapacity) return YES;
    NSUInteger newCapacity = run->heapVertexCapacity > 0 ? run->heapVertexCapacity : 8u;
    while (newCapacity < neededCount) {
        if (newCapacity > NSUIntegerMax / 2u) {
            newCapacity = neededCount;
            break;
        }
        newCapacity *= 2u;
    }
    if (newCapacity > NSUIntegerMax / sizeof(OrenAVMMetalTextVertex)) newCapacity = neededCount;
    OrenAVMMetalTextVertex* vertices = (OrenAVMMetalTextVertex*)realloc(run->heapVertices, newCapacity * sizeof(OrenAVMMetalTextVertex));
    if (!vertices) return NO;
    run->heapVertices = vertices;
    run->heapVertexCapacity = newCapacity;
    return YES;
}

static BOOL OrenAVMMetalImageRunAllocateExactHeapVertices(OrenAVMMetalImageRun* run, NSUInteger vertexCount) {
    if (!run || vertexCount == 0 || run->heapVertices || run->heapVertexCapacity != 0) return NO;
    if (vertexCount > NSUIntegerMax / sizeof(OrenAVMMetalTextVertex)) return NO;
    run->heapVertices = (OrenAVMMetalTextVertex*)malloc(vertexCount * sizeof(OrenAVMMetalTextVertex));
    if (!run->heapVertices) return NO;
    run->heapVertexCapacity = vertexCount;
    return YES;
}

static BOOL OrenAVMMetalImageRunAppendVertices(OrenAVMMetalImageRun* run,
                                               const OrenAVMMetalTextVertex* vertices,
                                               NSUInteger vertexCount) {
    if (!run) return NO;
    if (!vertices || vertexCount == 0) return YES;
    if (run->heapVertexCount > NSUIntegerMax - vertexCount) return NO;
    NSUInteger neededCount = run->heapVertexCount + vertexCount;
    if (!OrenAVMMetalImageRunReserveHeapVertices(run, neededCount)) return NO;
    memcpy(run->heapVertices + run->heapVertexCount, vertices, vertexCount * sizeof(OrenAVMMetalTextVertex));
    run->heapVertexCount = neededCount;
    return YES;
}

static OrenAVMMetalImageRun* OrenAVMMetalImageBatchRunCreate(id<MTLTexture> texture,
                                                             NSUInteger textureWidth,
                                                             NSUInteger textureHeight,
                                                             const uint8_t* rects,
                                                             uint32_t rectCount,
                                                             float tx,
                                                             float ty,
                                                             float opacity,
                                                             float logicalWidth,
                                                             float logicalHeight) {
    if (!texture || !rects || rectCount == 0) return nil;
    NSUInteger vertexCount = (NSUInteger)rectCount * 6u;
    if (vertexCount / 6u != (NSUInteger)rectCount) return nil;
    for (uint32_t ri = 0; ri < rectCount; ri++) {
        const uint8_t* r = rects + ((size_t)ri * 32u);
        uint32_t sx = OrenAVMMetalReadU32LE(r);
        uint32_t sy = OrenAVMMetalReadU32LE(r + 4);
        uint32_t sw = OrenAVMMetalReadU32LE(r + 8);
        uint32_t sh = OrenAVMMetalReadU32LE(r + 12);
        uint32_t dw = OrenAVMMetalReadU32LE(r + 24);
        uint32_t dh = OrenAVMMetalReadU32LE(r + 28);
        if (dw == 0 || dh == 0) return nil;
        if (!OrenAVMMetalSubrectInTexture(sx, sy, sw, sh, textureWidth, textureHeight)) return nil;
    }
    OrenAVMMetalImageRun* run = [[OrenAVMMetalImageRun alloc] init];
    if (!run) return nil;
    run.texture = texture;
    run.opacity = opacity;
    if (!OrenAVMMetalImageRunAllocateExactHeapVertices(run, vertexCount)) return nil;
    for (uint32_t ri = 0; ri < rectCount; ri++) {
        const uint8_t* r = rects + ((size_t)ri * 32u);
        uint32_t sx = OrenAVMMetalReadU32LE(r);
        uint32_t sy = OrenAVMMetalReadU32LE(r + 4);
        uint32_t sw = OrenAVMMetalReadU32LE(r + 8);
        uint32_t sh = OrenAVMMetalReadU32LE(r + 12);
        uint32_t dx = OrenAVMMetalReadU32LE(r + 16);
        uint32_t dy = OrenAVMMetalReadU32LE(r + 20);
        uint32_t dw = OrenAVMMetalReadU32LE(r + 24);
        uint32_t dh = OrenAVMMetalReadU32LE(r + 28);
        float u0 = (float)sx / (float)textureWidth;
        float v0 = (float)sy / (float)textureHeight;
        float u1 = (float)((uint64_t)sx + (uint64_t)sw) / (float)textureWidth;
        float v1 = (float)((uint64_t)sy + (uint64_t)sh) / (float)textureHeight;
        OrenAVMMetalWriteTextureQuad(run->heapVertices + run->heapVertexCount,
                                     (float)dx + tx,
                                     (float)dy + ty,
                                     (float)dw,
                                     (float)dh,
                                     logicalWidth,
                                     logicalHeight,
                                     u0,
                                     v0,
                                     u1,
                                     v1);
        run->heapVertexCount += 6u;
    }
    return run;
}

const void* OrenAVMMetalImageRunVertexBytes(OrenAVMMetalImageRun* run) {
    if (!run) return NULL;
    if (run->heapVertexCount != 0) return run->heapVertices;
    return run->inlineVertexCount == 0 ? NULL : run->vertices;
}

NSUInteger OrenAVMMetalImageRunVertexBytesLength(OrenAVMMetalImageRun* run) {
    if (!run) return 0;
    if (run->heapVertexCount != 0) return run->heapVertexCount * sizeof(OrenAVMMetalTextVertex);
    return run->inlineVertexCount * sizeof(OrenAVMMetalTextVertex);
}

NSUInteger OrenAVMMetalImageRunVertexCount(OrenAVMMetalImageRun* run) {
    return OrenAVMMetalImageRunVertexBytesLength(run) / sizeof(OrenAVMMetalTextVertex);
}

static BOOL OrenAVMMetalImageScissorEqual(OrenAVMMetalImageRun* a, OrenAVMMetalImageRun* b) {
    if (a.hasScissor != b.hasScissor) return NO;
    if (!a.hasScissor) return YES;
    return a.scissor.x == b.scissor.x &&
           a.scissor.y == b.scissor.y &&
           a.scissor.width == b.scissor.width &&
           a.scissor.height == b.scissor.height;
}

static BOOL OrenAVMMetalEnsureHeapImageVerticesForCoalescing(OrenAVMMetalImageRun* pending) {
    if (!pending) return NO;
    if (pending->heapVertexCount != 0) return YES;
    if (pending->inlineVertexCount == 0) return YES;
    if (!OrenAVMMetalImageRunAppendVertices(pending, pending->vertices, pending->inlineVertexCount)) return NO;
    pending->inlineVertexCount = 0;
    return YES;
}

NSArray<OrenAVMMetalImageRun*>* OrenAVMMetalCoalesceImageRuns(NSArray<OrenAVMMetalImageRun*>* runs) {
    if (runs.count < 2) return runs ?: @[];
    NSMutableArray<OrenAVMMetalImageRun*>* out = [NSMutableArray arrayWithCapacity:runs.count];
    OrenAVMMetalImageRun* pending = nil;
    for (OrenAVMMetalImageRun* run in runs) {
        NSUInteger vertexBytes = OrenAVMMetalImageRunVertexBytesLength(run);
        const void* vertexData = OrenAVMMetalImageRunVertexBytes(run);
        if (!run.texture || vertexBytes == 0 || !vertexData) continue;
        BOOL same = pending &&
            pending.texture == run.texture &&
            pending.opacity == run.opacity &&
            OrenAVMMetalImageScissorEqual(pending, run);
        if (!same) {
            pending = run;
            [out addObject:pending];
            continue;
        }
        if (!OrenAVMMetalEnsureHeapImageVerticesForCoalescing(pending) ||
            !OrenAVMMetalImageRunAppendVertices(pending,
                                                (const OrenAVMMetalTextVertex*)vertexData,
                                                vertexBytes / sizeof(OrenAVMMetalTextVertex))) {
            pending = run;
            [out addObject:pending];
        }
    }
    return out;
}

static BOOL OrenAVMMetalAppendImageRun(NSMutableArray<OrenAVMMetalImageRun*>** imageRuns,
                                       NSUInteger runCapacity,
                                       OrenAVMMetalImageRun* run,
                                       BOOL hasScissor,
                                       MTLScissorRect scissor) {
    if (!run) return YES;
    run.hasScissor = hasScissor;
    run.scissor = scissor;
    NSMutableArray* runs = OrenAVMMetalEnsureRunArray((NSMutableArray**)imageRuns, runCapacity);
    if (!runs) return NO;
    [runs addObject:run];
    return YES;
}

BOOL OrenAVMMetalHandleImageCommand(CFMutableDictionaryRef* imagesByID,
                                    id<MTLDevice> device,
                                    uint8_t opcode,
                                    const uint8_t* payload,
                                    uint16_t payloadLen,
                                    NSMutableArray<OrenAVMMetalImageRun*>** imageRuns,
                                    NSUInteger runCapacity,
                                    BOOL hasScissor,
                                    MTLScissorRect scissor,
                                    float tx,
                                    float ty,
                                    float logicalWidth,
                                    float logicalHeight,
                                    float opacity,
                                    NSUInteger retainedImageCountLimit,
                                    NSUInteger retainedImagePixelLimit,
                                    NSUInteger* retainedImagePixelCount) {
    if (!payload) return NO;
    switch (opcode) {
        case 64: {
            if (payloadLen >= 16) {
                uint32_t imageLen = OrenAVMMetalReadU32LE(payload + 12);
                if (imageLen == (uint32_t)payloadLen - 16u) {
                    (void)OrenAVMMetalPutImageResource(imagesByID,
                                                       device,
                                                       OrenAVMMetalReadU32LE(payload),
                                                       OrenAVMMetalReadU32LE(payload + 4),
                                                       OrenAVMMetalReadU32LE(payload + 8),
                                                       payload + 16,
                                                       imageLen,
                                                       retainedImageCountLimit,
                                                       retainedImagePixelLimit,
                                                       retainedImagePixelCount);
                }
            }
            return YES;
        }
        case 65: {
            if (opacity <= 0.0f) return YES;
            if (payloadLen == 20) {
                uint32_t dw = OrenAVMMetalReadU32LE(payload + 12);
                uint32_t dh = OrenAVMMetalReadU32LE(payload + 16);
                if (dw == 0 || dh == 0) return YES;
                OrenAVMMetalImageResource* image = OrenAVMMetalRetainedImageResource(imagesByID ? *imagesByID : NULL,
                                                                                     OrenAVMMetalReadU32LE(payload));
                id<MTLTexture> texture = image.texture;
                if (texture) {
                    NSUInteger textureWidth = texture.width;
                    NSUInteger textureHeight = texture.height;
                    if (!OrenAVMMetalAppendImageRun(imageRuns,
                                                    runCapacity,
                                                    OrenAVMMetalImageRunCreate(texture,
                                                                               textureWidth,
                                                                               textureHeight,
                                                                               0,
                                                                               0,
                                                                               (uint32_t)textureWidth,
                                                                               (uint32_t)textureHeight,
                                                                               (float)OrenAVMMetalReadU32LE(payload + 4) + tx,
                                                                               (float)OrenAVMMetalReadU32LE(payload + 8) + ty,
                                                                               (float)dw,
                                                                               (float)dh,
                                                                               opacity,
                                                                               logicalWidth,
                                                                               logicalHeight),
                                                    hasScissor,
                                                    scissor)) {
                        return NO;
                    }
                }
            }
            return YES;
        }
        case 66: {
            if (payloadLen == 4) {
                OrenAVMMetalRemoveImageResource(imagesByID ? *imagesByID : NULL,
                                                OrenAVMMetalReadU32LE(payload),
                                                retainedImagePixelCount);
            }
            return YES;
        }
        case 67: {
            if (opacity <= 0.0f) return YES;
            if (payloadLen == 36) {
                uint32_t sw = OrenAVMMetalReadU32LE(payload + 12);
                uint32_t sh = OrenAVMMetalReadU32LE(payload + 16);
                uint32_t dw = OrenAVMMetalReadU32LE(payload + 28);
                uint32_t dh = OrenAVMMetalReadU32LE(payload + 32);
                if (sw == 0 || sh == 0 || dw == 0 || dh == 0) return YES;
                OrenAVMMetalImageResource* image = OrenAVMMetalRetainedImageResource(imagesByID ? *imagesByID : NULL,
                                                                                     OrenAVMMetalReadU32LE(payload));
                id<MTLTexture> texture = image.texture;
                if (texture) {
                    NSUInteger textureWidth = texture.width;
                    NSUInteger textureHeight = texture.height;
                    if (!OrenAVMMetalAppendImageRun(imageRuns,
                                                    runCapacity,
                                                    OrenAVMMetalImageRunCreate(texture,
                                                                               textureWidth,
                                                                               textureHeight,
                                                                               OrenAVMMetalReadU32LE(payload + 4),
                                                                               OrenAVMMetalReadU32LE(payload + 8),
                                                                               sw,
                                                                               sh,
                                                                               (float)OrenAVMMetalReadU32LE(payload + 20) + tx,
                                                                               (float)OrenAVMMetalReadU32LE(payload + 24) + ty,
                                                                               (float)dw,
                                                                               (float)dh,
                                                                               opacity,
                                                                               logicalWidth,
                                                                               logicalHeight),
                                                    hasScissor,
                                                    scissor)) {
                        return NO;
                    }
                }
            }
            return YES;
        }
        case 71: {
            if (opacity <= 0.0f) return YES;
            if (payloadLen >= 40 && ((payloadLen - 8) % 32) == 0) {
                uint32_t rectCount = OrenAVMMetalReadU32LE(payload + 4);
                if (rectCount == ((uint32_t)payloadLen - 8u) / 32u) {
                    if (OrenAVMMetalImageRectsHaveZeroSize(payload + 8, rectCount)) return YES;
                    OrenAVMMetalImageResource* image = OrenAVMMetalRetainedImageResource(imagesByID ? *imagesByID : NULL,
                                                                                         OrenAVMMetalReadU32LE(payload));
                    id<MTLTexture> texture = image.texture;
                    if (texture) {
                        NSUInteger textureWidth = texture.width;
                        NSUInteger textureHeight = texture.height;
                        if (rectCount == 1) {
                            const uint8_t* r = payload + 8;
                            if (!OrenAVMMetalAppendImageRun(imageRuns,
                                                            runCapacity,
                                                            OrenAVMMetalImageRunCreate(texture,
                                                                                       textureWidth,
                                                                                       textureHeight,
                                                                                       OrenAVMMetalReadU32LE(r),
                                                                                       OrenAVMMetalReadU32LE(r + 4),
                                                                                       OrenAVMMetalReadU32LE(r + 8),
                                                                                       OrenAVMMetalReadU32LE(r + 12),
                                                                                       (float)OrenAVMMetalReadU32LE(r + 16) + tx,
                                                                                       (float)OrenAVMMetalReadU32LE(r + 20) + ty,
                                                                                       (float)OrenAVMMetalReadU32LE(r + 24),
                                                                                       (float)OrenAVMMetalReadU32LE(r + 28),
                                                                                       opacity,
                                                                                       logicalWidth,
                                                                                       logicalHeight),
                                                            hasScissor,
                                                            scissor)) {
                                return NO;
                            }
                        } else {
                            if (!OrenAVMMetalAppendImageRun(imageRuns,
                                                            runCapacity,
                                                            OrenAVMMetalImageBatchRunCreate(texture,
                                                                                            textureWidth,
                                                                                            textureHeight,
                                                                                            payload + 8,
                                                                                            rectCount,
                                                                                            tx,
                                                                                            ty,
                                                                                            opacity,
                                                                                            logicalWidth,
                                                                                            logicalHeight),
                                                            hasScissor,
                                                            scissor)) {
                                return NO;
                            }
                        }
                    }
                }
            }
            return YES;
        }
        default:
            return NO;
    }
}

const void* OrenAVMMetalRetainedTextKey(uint32_t textID) {
    return OrenAVMMetalRetainedKey(textID);
}

OrenAVMMetalTextResource* OrenAVMMetalRetainedTextResource(CFDictionaryRef texts, uint32_t textID) {
    if (!texts || textID == 0) return nil;
    return (__bridge OrenAVMMetalTextResource*)CFDictionaryGetValue(texts, OrenAVMMetalRetainedTextKey(textID));
}

BOOL OrenAVMMetalPutTextResource(CFMutableDictionaryRef* texts,
                                 uint32_t textID,
                                 uint32_t rgbaValue,
                                 const uint8_t* textBytes,
                                 uint32_t textLen) {
    if (!texts || textID == 0 || !textBytes || textLen == 0) return NO;
    if (!OrenAVMMetalEnsureRetainedResourceMap(texts)) return NO;
    NSString* text = [[NSString alloc] initWithBytes:textBytes
                                             length:(NSUInteger)textLen
                                           encoding:NSUTF8StringEncoding];
    if (!text) return NO;
    OrenAVMMetalTextResource* resource = [[OrenAVMMetalTextResource alloc] init];
    if (!resource) return NO;
    resource.text = text;
    resource.rgbaValue = rgbaValue;
    CFDictionarySetValue(*texts, OrenAVMMetalRetainedTextKey(textID), (__bridge const void*)resource);
    return YES;
}

void OrenAVMMetalRemoveTextResource(CFMutableDictionaryRef texts, uint32_t textID) {
    if (texts && textID != 0) CFDictionaryRemoveValue(texts, OrenAVMMetalRetainedTextKey(textID));
}

static BOOL OrenAVMMetalAppendTextRun(NSMutableArray<OrenAVMMetalTextRun*>** textRuns,
                                      NSUInteger runCapacity,
                                      OrenAVMMetalTextRun* run,
                                      BOOL hasScissor,
                                      MTLScissorRect scissor) {
    if (!run) return YES;
    run.hasScissor = hasScissor;
    run.scissor = scissor;
    NSMutableArray* runs = OrenAVMMetalEnsureRunArray((NSMutableArray**)textRuns, runCapacity);
    if (!runs) return NO;
    [runs addObject:run];
    return YES;
}

BOOL OrenAVMMetalHandleTextCommand(CFMutableDictionaryRef* texts,
                                   id<MTLDevice> device,
                                   UIScreen* screen,
                                   uint8_t opcode,
                                   const uint8_t* payload,
                                   uint16_t payloadLen,
                                   OrenAVMMetalTextAtlas** textAtlas,
                                   NSMutableDictionary<OrenAVMMetalTextCacheKey*, OrenAVMMetalTextCacheEntry*>* textCache,
                                   NSMutableArray<OrenAVMMetalTextCacheKey*>* textCacheOrder,
                                   OrenAVMMetalTextAttributeCache* textAttributes,
                                   NSUInteger* textCachePixels,
                                   NSMutableArray<OrenAVMMetalTextRun*>** textRuns,
                                   NSUInteger runCapacity,
                                   BOOL hasScissor,
                                   MTLScissorRect scissor,
                                   float tx,
                                   float ty,
                                   float logicalWidth,
                                   float logicalHeight,
                                   float opacity) {
    if (!payload) return NO;
    switch (opcode) {
        case 2: {
            if (opacity <= 0.0f) return YES;
            if (payloadLen >= 16) {
                uint32_t textLen = OrenAVMMetalReadU32LE(payload + 12);
                if (textLen == (uint32_t)payloadLen - 16u && textLen > 0) {
                    NSString* text = [[NSString alloc] initWithBytes:payload + 16
                                                              length:(NSUInteger)textLen
                                                            encoding:NSUTF8StringEncoding];
                    if (!OrenAVMMetalAppendTextRun(textRuns,
                                                   runCapacity,
                                                   OrenAVMMetalCreateTextRun(device,
                                                                             screen,
                                                                             textAtlas,
                                                                             textCache,
                                                                             textCacheOrder,
                                                                             textAttributes,
                                                                             textCachePixels,
                                                                             text,
                                                                             (float)OrenAVMMetalReadU32LE(payload) + tx,
                                                                             (float)OrenAVMMetalReadU32LE(payload + 4) + ty,
                                                                             payload + 8,
                                                                             opacity,
                                                                             logicalWidth,
                                                                             logicalHeight),
                                                   hasScissor,
                                                   scissor)) {
                        return NO;
                    }
                }
            }
            return YES;
        }
        case 68: {
            if (payloadLen >= 12) {
                uint32_t textLen = OrenAVMMetalReadU32LE(payload + 8);
                if (textLen == (uint32_t)payloadLen - 12u && textLen > 0) {
                    (void)OrenAVMMetalPutTextResource(texts,
                                                      OrenAVMMetalReadU32LE(payload),
                                                      OrenAVMMetalReadU32LE(payload + 4),
                                                      payload + 12,
                                                      textLen);
                }
            }
            return YES;
        }
        case 69: {
            if (opacity <= 0.0f) return YES;
            if (payloadLen == 12) {
                OrenAVMMetalTextResource* resource = OrenAVMMetalRetainedTextResource(texts ? *texts : NULL,
                                                                                      OrenAVMMetalReadU32LE(payload));
                if (resource.text) {
                    uint8_t textRGBA[4];
                    OrenAVMMetalRGBAValueBytes(resource.rgbaValue, textRGBA);
                    if (!OrenAVMMetalAppendTextRun(textRuns,
                                                   runCapacity,
                                                   OrenAVMMetalCreateTextRun(device,
                                                                             screen,
                                                                             textAtlas,
                                                                             textCache,
                                                                             textCacheOrder,
                                                                             textAttributes,
                                                                             textCachePixels,
                                                                             resource.text,
                                                                             (float)OrenAVMMetalReadU32LE(payload + 4) + tx,
                                                                             (float)OrenAVMMetalReadU32LE(payload + 8) + ty,
                                                                             textRGBA,
                                                                             opacity,
                                                                             logicalWidth,
                                                                             logicalHeight),
                                                   hasScissor,
                                                   scissor)) {
                        return NO;
                    }
                }
            }
            return YES;
        }
        case 70: {
            if (payloadLen == 4) {
                OrenAVMMetalRemoveTextResource(texts ? *texts : NULL, OrenAVMMetalReadU32LE(payload));
            }
            return YES;
        }
        case 72: {
            if (opacity <= 0.0f) return YES;
            if (payloadLen >= 16 && ((payloadLen - 8) % 8) == 0) {
                uint32_t textID = OrenAVMMetalReadU32LE(payload);
                uint32_t posCount = OrenAVMMetalReadU32LE(payload + 4);
                if (posCount == ((uint32_t)payloadLen - 8u) / 8u) {
                    OrenAVMMetalTextResource* resource = OrenAVMMetalRetainedTextResource(texts ? *texts : NULL, textID);
                    if (!resource.text) return YES;
                    uint8_t textRGBA[4];
                    OrenAVMMetalRGBAValueBytes(resource.rgbaValue, textRGBA);
                    if (!OrenAVMMetalAppendTextRun(textRuns,
                                                   runCapacity,
                                                   OrenAVMMetalCreateTextBatchRun(device,
                                                                                  screen,
                                                                                  textAtlas,
                                                                                  textCache,
                                                                                  textCacheOrder,
                                                                                  textAttributes,
                                                                                  textCachePixels,
                                                                                  resource.text,
                                                                                  payload + 8,
                                                                                  posCount,
                                                                                  tx,
                                                                                  ty,
                                                                                  textRGBA,
                                                                                  opacity,
                                                                                  logicalWidth,
                                                                                  logicalHeight),
                                                   hasScissor,
                                                   scissor)) {
                        return NO;
                    }
                }
            }
            return YES;
        }
        default:
            return NO;
    }
}

const void* OrenAVMMetalRetainedMeshKey(uint32_t meshID) {
    return OrenAVMMetalRetainedKey(meshID);
}

OrenAVMMetalMesh2DResource* OrenAVMMetalRetainedMesh2DResource(CFDictionaryRef meshes, uint32_t meshID) {
    if (!meshes || meshID == 0) return nil;
    return (__bridge OrenAVMMetalMesh2DResource*)CFDictionaryGetValue(meshes, OrenAVMMetalRetainedMeshKey(meshID));
}

OrenAVMMetalMesh3DResource* OrenAVMMetalRetainedMesh3DResource(CFDictionaryRef meshes, uint32_t meshID) {
    if (!meshes || meshID == 0) return nil;
    return (__bridge OrenAVMMetalMesh3DResource*)CFDictionaryGetValue(meshes, OrenAVMMetalRetainedMeshKey(meshID));
}

static BOOL OrenAVMMetalTriangleOrderAppend(OrenAVMMetalTriangleOrder** order,
                                            OrenAVMMetalTriangleOrder* inlineOrder,
                                            uint32_t* capacity,
                                            OrenAVMMetalTriangleOrder** heapStorage,
                                            uint32_t* count,
                                            uint32_t triangle,
                                            int64_t zsum);

void OrenAVMMetalAppendMesh2DResource(OrenAVMMetalMesh2DResource* mesh,
                                      OrenAVMMetalVertexBuffer* vertices,
                                      float tx,
                                      float ty,
                                      float logicalWidth,
                                      float logicalHeight,
                                      float opacity) {
    if (!mesh || !vertices || opacity <= 0.0f) return;
    const uint8_t* tris = mesh.triangles;
    if (!tris || mesh.triangleCount != mesh.triangleBytes / 24u) return;
    uint8_t rgba[4];
    OrenAVMMetalRGBAValueWithOpacity(mesh.rgbaValue, opacity, rgba);
    for (uint32_t ti = 0; ti < mesh.triangleCount; ti++) {
        const uint8_t* tri = tris + ((size_t)ti * 24u);
        OrenAVMMetalAppendTriangle(vertices,
                                   (float)OrenAVMMetalReadU32LE(tri) + tx,
                                   (float)OrenAVMMetalReadU32LE(tri + 4) + ty,
                                   (float)OrenAVMMetalReadU32LE(tri + 8) + tx,
                                   (float)OrenAVMMetalReadU32LE(tri + 12) + ty,
                                   (float)OrenAVMMetalReadU32LE(tri + 16) + tx,
                                   (float)OrenAVMMetalReadU32LE(tri + 20) + ty,
                                   logicalWidth,
                                   logicalHeight,
                                   rgba);
    }
}

void OrenAVMMetalAppendMesh3DResource(CFDictionaryRef meshes,
                                      CFDictionaryRef materials,
                                      CFDictionaryRef models,
                                      uint32_t opcode,
                                      const uint8_t* payload,
                                      OrenAVMMetalVertexBuffer* vertices,
                                      float tx,
                                      float ty,
                                      float logicalWidth,
                                      float logicalHeight,
                                      float opacity,
                                      BOOL depthEnabled,
                                      int32_t nearZ,
                                      int32_t farZ) {
    if (!payload || !vertices || opacity <= 0.0f) return;
    uint32_t meshID = OrenAVMMetalReadU32LE(payload);
    uint32_t materialID = 0;
    int32_t modelX = 0;
    int32_t modelY = 0;
    int32_t modelZ = 0;
    uint32_t scaleMilli = 1000u;
    if (opcode == 94) {
        OrenAVMMetalModelResource* model = OrenAVMMetalRetainedModelResource(models, meshID);
        if (!model) return;
        meshID = model.meshID;
        materialID = model.materialID;
        modelX = model.x;
        modelY = model.y;
        modelZ = model.z;
        scaleMilli = model.scaleMilli;
    }
    OrenAVMMetalMesh3DResource* mesh = OrenAVMMetalRetainedMesh3DResource(meshes, meshID);
    BOOL hasMaterialRGBA = NO;
    uint32_t materialRGBAOverride = 0;
    if (opcode == 90 || opcode == 91) {
        materialID = OrenAVMMetalReadU32LE(payload + 4);
    }
    if (materialID != 0) {
        hasMaterialRGBA = OrenAVMMetalRetainedMaterialRGBA(materials, materialID, &materialRGBAOverride);
        if (!hasMaterialRGBA) return;
    }
    uint32_t materialRGBA = hasMaterialRGBA ? materialRGBAOverride : mesh.rgbaValue;
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
    uint8_t rgba[4];
    if (verts && idx && mesh.hasRGBA && scaleMilli != 0 && mesh.indexCount == mesh.indexBytes / 4u) {
        uint32_t triangleTotal = mesh.indexCount / 3u;
        OrenAVMMetalTriangleOrder inlineOrder[OrenAVMMetalInlineTriangleOrderCapacity];
        OrenAVMMetalTriangleOrder* order = inlineOrder;
        OrenAVMMetalTriangleOrder* heapOrder = NULL;
        uint32_t orderCapacity = OrenAVMMetalInlineTriangleOrderCapacity;
        uint32_t visibleTotal = 0;
        for (uint32_t ti = 0; ti < triangleTotal; ti++) {
            int64_t z = OrenAVMMetalMesh3DIndexedZSumModel(verts, idx, ti, modelZ, scaleMilli);
            if (!OrenAVMMetalMesh3DZVisible(z, depthEnabled, nearZ, farZ)) continue;
            if (!OrenAVMMetalTriangleOrderAppend(&order, inlineOrder, &orderCapacity, &heapOrder, &visibleTotal, ti, z)) {
                free(heapOrder);
                return;
            }
        }
        if (visibleTotal == 0) {
            free(heapOrder);
            return;
        }
        OrenAVMMetalRGBAValueWithOpacity(materialRGBA, opacity, rgba);
        OrenAVMMetalSortTriangleOrder(order, visibleTotal);
        for (uint32_t di = 0; di < visibleTotal; di++) {
            uint32_t best = order[di].triangle;
            const uint8_t* tri = idx + ((size_t)best * 12u);
            const uint8_t* v1 = verts + ((size_t)OrenAVMMetalReadU32LE(tri) * 12u);
            const uint8_t* v2 = verts + ((size_t)OrenAVMMetalReadU32LE(tri + 4) * 12u);
            const uint8_t* v3 = verts + ((size_t)OrenAVMMetalReadU32LE(tri + 8) * 12u);
            OrenAVMMetalAppendTriangle(vertices,
                                       OrenAVMMetalMesh3DModelCoord(v1, modelX, scaleMilli) + tx,
                                       OrenAVMMetalMesh3DModelCoord(v1 + 4, modelY, scaleMilli) + ty,
                                       OrenAVMMetalMesh3DModelCoord(v2, modelX, scaleMilli) + tx,
                                       OrenAVMMetalMesh3DModelCoord(v2 + 4, modelY, scaleMilli) + ty,
                                       OrenAVMMetalMesh3DModelCoord(v3, modelX, scaleMilli) + tx,
                                       OrenAVMMetalMesh3DModelCoord(v3 + 4, modelY, scaleMilli) + ty,
                                       logicalWidth,
                                       logicalHeight,
                                       rgba);
        }
        free(heapOrder);
    } else if (tris && scaleMilli != 0 && (meshStride == 36u || meshStride == 40u) && mesh.triangleCount == mesh.triangleBytes / meshStride) {
        uint8_t constantRGBA[4];
        BOOL hasConstantRGBA = hasMaterialRGBA || (meshStride == 36u && mesh.hasRGBA);
        uint32_t triangleTotal = mesh.triangleCount;
        OrenAVMMetalTriangleOrder inlineOrder[OrenAVMMetalInlineTriangleOrderCapacity];
        OrenAVMMetalTriangleOrder* order = inlineOrder;
        OrenAVMMetalTriangleOrder* heapOrder = NULL;
        uint32_t orderCapacity = OrenAVMMetalInlineTriangleOrderCapacity;
        uint32_t visibleTotal = 0;
        for (uint32_t ti = 0; ti < triangleTotal; ti++) {
            int64_t z = OrenAVMMetalMesh3DZSumModel(tris + ((size_t)ti * meshStride), modelZ, scaleMilli);
            if (!OrenAVMMetalMesh3DZVisible(z, depthEnabled, nearZ, farZ)) continue;
            if (!OrenAVMMetalTriangleOrderAppend(&order, inlineOrder, &orderCapacity, &heapOrder, &visibleTotal, ti, z)) {
                free(heapOrder);
                return;
            }
        }
        if (visibleTotal == 0) {
            free(heapOrder);
            return;
        }
        if (hasConstantRGBA) {
            OrenAVMMetalRGBAValueWithOpacity(hasMaterialRGBA ? materialRGBA : mesh.rgbaValue,
                                             opacity,
                                             constantRGBA);
        }
        OrenAVMMetalSortTriangleOrder(order, visibleTotal);
        for (uint32_t di = 0; di < visibleTotal; di++) {
            uint32_t best = order[di].triangle;
            const uint8_t* tri = tris + ((size_t)best * meshStride);
            const uint8_t* triangleRGBA = NULL;
            if (hasConstantRGBA) {
                triangleRGBA = constantRGBA;
            } else if (meshStride == 40u) {
                OrenAVMMetalRGBAWithOpacity(tri + 36, opacity, rgba);
                triangleRGBA = rgba;
            } else {
                continue;
            }
            OrenAVMMetalAppendTriangle(vertices,
                                       OrenAVMMetalMesh3DModelCoord(tri, modelX, scaleMilli) + tx,
                                       OrenAVMMetalMesh3DModelCoord(tri + 4, modelY, scaleMilli) + ty,
                                       OrenAVMMetalMesh3DModelCoord(tri + 12, modelX, scaleMilli) + tx,
                                       OrenAVMMetalMesh3DModelCoord(tri + 16, modelY, scaleMilli) + ty,
                                       OrenAVMMetalMesh3DModelCoord(tri + 24, modelX, scaleMilli) + tx,
                                       OrenAVMMetalMesh3DModelCoord(tri + 28, modelY, scaleMilli) + ty,
                                       logicalWidth,
                                       logicalHeight,
                                       triangleRGBA);
        }
        free(heapOrder);
    }
}

BOOL OrenAVMMetalHandleMeshCommand(CFMutableDictionaryRef* meshes2D,
                                   CFMutableDictionaryRef* meshes3D,
                                   CFMutableDictionaryRef* materials,
                                   CFMutableDictionaryRef* models,
                                   uint8_t opcode,
                                   const uint8_t* payload,
                                   uint16_t payloadLen,
                                   OrenAVMMetalVertexBuffer* vertices,
                                   float tx,
                                   float ty,
                                   float logicalWidth,
                                   float logicalHeight,
                                   float opacity,
                                   BOOL depthEnabled,
                                   int32_t nearZ,
                                   int32_t farZ) {
    if (!payload) return NO;
    switch (opcode) {
        case 80: {
            if (payloadLen >= 36 && ((payloadLen - 12) % 24) == 0) {
                uint32_t meshID = OrenAVMMetalReadU32LE(payload);
                uint32_t triangleCount = OrenAVMMetalReadU32LE(payload + 8);
                if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 12u) / 24u) {
                    (void)OrenAVMMetalPutMesh2DResource(meshes2D,
                                                        meshID,
                                                        OrenAVMMetalReadU32LE(payload + 4),
                                                        payload + 12,
                                                        (NSUInteger)payloadLen - 12u,
                                                        triangleCount);
                }
            }
            return YES;
        }
        case 81: {
            if (payloadLen == 4) {
                OrenAVMMetalMesh2DResource* mesh = OrenAVMMetalRetainedMesh2DResource(meshes2D ? *meshes2D : NULL,
                                                                                      OrenAVMMetalReadU32LE(payload));
                OrenAVMMetalAppendMesh2DResource(mesh, vertices, tx, ty, logicalWidth, logicalHeight, opacity);
            }
            return YES;
        }
        case 82: {
            if (payloadLen == 4) OrenAVMMetalRemoveMeshResource(meshes2D ? *meshes2D : NULL, OrenAVMMetalReadU32LE(payload));
            return YES;
        }
        case 83: {
            if (payloadLen >= 48 && ((payloadLen - 12) % 36) == 0) {
                uint32_t meshID = OrenAVMMetalReadU32LE(payload);
                uint32_t triangleCount = OrenAVMMetalReadU32LE(payload + 8);
                if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 12u) / 36u) {
                    (void)OrenAVMMetalPutPackedMesh3DResource(meshes3D,
                                                              meshID,
                                                              OrenAVMMetalReadU32LE(payload + 4),
                                                              YES,
                                                              payload + 12,
                                                              (NSUInteger)payloadLen - 12u,
                                                              triangleCount,
                                                              36u);
                }
            }
            return YES;
        }
        case 84:
        case 87:
        case 90:
        case 91:
        case 94: {
            BOOL valid = (opcode == 84 && payloadLen == 4) || (opcode == 87 && payloadLen == 20) ||
                         (opcode == 90 && payloadLen == 8) || (opcode == 91 && payloadLen == 24) ||
                         (opcode == 94 && payloadLen == 4);
            if (valid) {
                OrenAVMMetalAppendMesh3DResource(meshes3D ? *meshes3D : NULL,
                                                 materials ? *materials : NULL,
                                                 models ? *models : NULL,
                                                 opcode,
                                                 payload,
                                                 vertices,
                                                 tx,
                                                 ty,
                                                 logicalWidth,
                                                 logicalHeight,
                                                 opacity,
                                                 depthEnabled,
                                                 nearZ,
                                                 farZ);
            }
            return YES;
        }
        case 85: {
            if (payloadLen == 4) OrenAVMMetalRemoveMeshResource(meshes3D ? *meshes3D : NULL, OrenAVMMetalReadU32LE(payload));
            return YES;
        }
        case 86: {
            if (payloadLen >= 48 && ((payloadLen - 8) % 40) == 0) {
                uint32_t meshID = OrenAVMMetalReadU32LE(payload);
                uint32_t triangleCount = OrenAVMMetalReadU32LE(payload + 4);
                if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 8u) / 40u) {
                    (void)OrenAVMMetalPutPackedMesh3DResource(meshes3D,
                                                              meshID,
                                                              0,
                                                              NO,
                                                              payload + 8,
                                                              (NSUInteger)payloadLen - 8u,
                                                              triangleCount,
                                                              40u);
                }
            }
            return YES;
        }
        case 88: {
            if (payloadLen >= 64) {
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
                    (void)OrenAVMMetalPutIndexedMesh3DResource(meshes3D,
                                                               meshID,
                                                               OrenAVMMetalReadU32LE(payload + 4),
                                                               payload + 16,
                                                               vertexBytes,
                                                               payload + 16 + vertexBytes,
                                                               indexBytes,
                                                               indexCount);
                }
            }
            return YES;
        }
        case 89: {
            if (payloadLen == 8) {
                (void)OrenAVMMetalPutMaterialResource(materials,
                                                      OrenAVMMetalReadU32LE(payload),
                                                      OrenAVMMetalReadU32LE(payload + 4));
            }
            return YES;
        }
        case 92: {
            if (payloadLen == 4) OrenAVMMetalRemoveMaterialResource(materials ? *materials : NULL, OrenAVMMetalReadU32LE(payload));
            return YES;
        }
        case 93: {
            if (payloadLen == 28) {
                (void)OrenAVMMetalPutModelResource(models,
                                                   OrenAVMMetalReadU32LE(payload),
                                                   OrenAVMMetalReadU32LE(payload + 4),
                                                   OrenAVMMetalReadU32LE(payload + 8),
                                                   (int32_t)OrenAVMMetalReadU32LE(payload + 12),
                                                   (int32_t)OrenAVMMetalReadU32LE(payload + 16),
                                                   (int32_t)OrenAVMMetalReadU32LE(payload + 20),
                                                   OrenAVMMetalReadU32LE(payload + 24));
            }
            return YES;
        }
        case 95: {
            if (payloadLen == 4) OrenAVMMetalRemoveModelResource(models ? *models : NULL, OrenAVMMetalReadU32LE(payload));
            return YES;
        }
        default:
            return NO;
    }
}

BOOL OrenAVMMetalPutMesh2DResource(CFMutableDictionaryRef* meshes,
                                   uint32_t meshID,
                                   uint32_t rgbaValue,
                                   const uint8_t* triangles,
                                   NSUInteger triangleBytes,
                                   uint32_t triangleCount) {
    if (!meshes || meshID == 0 || !triangles || triangleBytes == 0) return NO;
    if (!OrenAVMMetalEnsureRetainedResourceMap(meshes)) return NO;
    uint8_t* triangleCopy = OrenAVMMetalCopyPayloadBytes(triangles, triangleBytes);
    if (!triangleCopy) return NO;
    OrenAVMMetalMesh2DResource* mesh = [[OrenAVMMetalMesh2DResource alloc] init];
    if (!mesh) {
        free(triangleCopy);
        return NO;
    }
    mesh.rgbaValue = rgbaValue;
    mesh.triangleBytes = triangleBytes;
    mesh.triangles = triangleCopy;
    mesh.triangleCount = triangleCount;
    CFDictionarySetValue(*meshes, OrenAVMMetalRetainedMeshKey(meshID), (__bridge const void*)mesh);
    return YES;
}

void OrenAVMMetalRemoveMeshResource(CFMutableDictionaryRef meshes, uint32_t meshID) {
    if (meshes && meshID != 0) CFDictionaryRemoveValue(meshes, OrenAVMMetalRetainedMeshKey(meshID));
}

BOOL OrenAVMMetalPutPackedMesh3DResource(CFMutableDictionaryRef* meshes,
                                         uint32_t meshID,
                                         uint32_t rgbaValue,
                                         BOOL hasRGBA,
                                         const uint8_t* triangles,
                                         NSUInteger triangleBytes,
                                         uint32_t triangleCount,
                                         uint32_t stride) {
    if (!meshes || meshID == 0 || !triangles || triangleBytes == 0) return NO;
    if (!OrenAVMMetalEnsureRetainedResourceMap(meshes)) return NO;
    uint8_t* triangleCopy = OrenAVMMetalCopyPayloadBytes(triangles, triangleBytes);
    if (!triangleCopy) return NO;
    OrenAVMMetalMesh3DResource* mesh = [[OrenAVMMetalMesh3DResource alloc] init];
    if (!mesh) {
        free(triangleCopy);
        return NO;
    }
    mesh.rgbaValue = rgbaValue;
    mesh.hasRGBA = hasRGBA;
    mesh.triangleBytes = triangleBytes;
    mesh.triangles = triangleCopy;
    mesh.triangleCount = triangleCount;
    mesh.stride = stride;
    CFDictionarySetValue(*meshes, OrenAVMMetalRetainedMeshKey(meshID), (__bridge const void*)mesh);
    return YES;
}

BOOL OrenAVMMetalPutIndexedMesh3DResource(CFMutableDictionaryRef* meshes,
                                          uint32_t meshID,
                                          uint32_t rgbaValue,
                                          const uint8_t* vertices,
                                          NSUInteger vertexBytes,
                                          const uint8_t* indices,
                                          NSUInteger indexBytes,
                                          uint32_t indexCount) {
    if (!meshes || meshID == 0 || !vertices || !indices || vertexBytes == 0 || indexBytes == 0) return NO;
    if (!OrenAVMMetalEnsureRetainedResourceMap(meshes)) return NO;
    uint8_t* vertexCopy = OrenAVMMetalCopyPayloadBytes(vertices, vertexBytes);
    if (!vertexCopy) return NO;
    uint8_t* indexCopy = OrenAVMMetalCopyPayloadBytes(indices, indexBytes);
    if (!indexCopy) {
        free(vertexCopy);
        return NO;
    }
    OrenAVMMetalMesh3DResource* mesh = [[OrenAVMMetalMesh3DResource alloc] init];
    if (!mesh) {
        free(vertexCopy);
        free(indexCopy);
        return NO;
    }
    mesh.rgbaValue = rgbaValue;
    mesh.hasRGBA = YES;
    mesh.vertexBytes = vertexBytes;
    mesh.indexBytes = indexBytes;
    mesh.vertices = vertexCopy;
    mesh.indices = indexCopy;
    mesh.indexCount = indexCount;
    CFDictionarySetValue(*meshes, OrenAVMMetalRetainedMeshKey(meshID), (__bridge const void*)mesh);
    return YES;
}

const void* OrenAVMMetalRetainedMaterialKey(uint32_t materialID) {
    return OrenAVMMetalRetainedKey(materialID);
}

const void* OrenAVMMetalRetainedMaterialValue(uint32_t rgbaValue) {
    return (const void*)(uintptr_t)((uint64_t)rgbaValue + 1ull);
}

BOOL OrenAVMMetalRetainedMaterialRGBA(CFDictionaryRef materials, uint32_t materialID, uint32_t* rgbaOut) {
    const void* stored = NULL;
    if (!materials || materialID == 0 || !CFDictionaryGetValueIfPresent(materials, OrenAVMMetalRetainedMaterialKey(materialID), &stored)) {
        return NO;
    }
    if (rgbaOut) *rgbaOut = (uint32_t)((uintptr_t)stored - 1ull);
    return YES;
}

BOOL OrenAVMMetalPutMaterialResource(CFMutableDictionaryRef* materials, uint32_t materialID, uint32_t rgbaValue) {
    if (!materials || materialID == 0) return NO;
    if (!OrenAVMMetalEnsureScalarResourceMap(materials)) return NO;
    CFDictionarySetValue(*materials, OrenAVMMetalRetainedMaterialKey(materialID), OrenAVMMetalRetainedMaterialValue(rgbaValue));
    return YES;
}

void OrenAVMMetalRemoveMaterialResource(CFMutableDictionaryRef materials, uint32_t materialID) {
    if (materials && materialID != 0) CFDictionaryRemoveValue(materials, OrenAVMMetalRetainedMaterialKey(materialID));
}

const void* OrenAVMMetalRetainedModelKey(uint32_t modelID) {
    return OrenAVMMetalRetainedKey(modelID);
}

OrenAVMMetalModelResource* OrenAVMMetalRetainedModelResource(CFDictionaryRef models, uint32_t modelID) {
    if (!models || modelID == 0) return nil;
    return (__bridge OrenAVMMetalModelResource*)CFDictionaryGetValue(models, OrenAVMMetalRetainedModelKey(modelID));
}

BOOL OrenAVMMetalPutModelResource(CFMutableDictionaryRef* models,
                                  uint32_t modelID,
                                  uint32_t meshID,
                                  uint32_t materialID,
                                  int32_t x,
                                  int32_t y,
                                  int32_t z,
                                  uint32_t scaleMilli) {
    if (!models || modelID == 0 || meshID == 0 || scaleMilli == 0) return NO;
    if (!OrenAVMMetalEnsureRetainedResourceMap(models)) return NO;
    OrenAVMMetalModelResource* model = [[OrenAVMMetalModelResource alloc] init];
    if (!model) return NO;
    model.meshID = meshID;
    model.materialID = materialID;
    model.x = x;
    model.y = y;
    model.z = z;
    model.scaleMilli = scaleMilli;
    CFDictionarySetValue(*models, OrenAVMMetalRetainedModelKey(modelID), (__bridge const void*)model);
    return YES;
}

void OrenAVMMetalRemoveModelResource(CFMutableDictionaryRef models, uint32_t modelID) {
    if (models && modelID != 0) CFDictionaryRemoveValue(models, OrenAVMMetalRetainedModelKey(modelID));
}

static int64_t OrenAVMMetalMesh3DZSum(const uint8_t* tri) {
    return (int64_t)(int32_t)OrenAVMMetalReadU32LE(tri + 8) +
           (int64_t)(int32_t)OrenAVMMetalReadU32LE(tri + 20) +
           (int64_t)(int32_t)OrenAVMMetalReadU32LE(tri + 32);
}

int64_t OrenAVMMetalMesh3DZSumModel(const uint8_t* tri, int32_t offset, uint32_t scaleMilli) {
    return (OrenAVMMetalMesh3DZSum(tri) * (int64_t)scaleMilli) / 1000 + (int64_t)offset * 3;
}

BOOL OrenAVMMetalMesh3DZVisible(int64_t zsum, BOOL depthEnabled, int32_t nearZ, int32_t farZ) {
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

void OrenAVMMetalSortTriangleOrder(OrenAVMMetalTriangleOrder* order, uint32_t count) {
    if (count > 1) qsort(order, count, sizeof(OrenAVMMetalTriangleOrder), OrenAVMMetalTriangleOrderCompare);
}

static BOOL OrenAVMMetalTriangleOrderAppend(OrenAVMMetalTriangleOrder** order,
                                            OrenAVMMetalTriangleOrder* inlineOrder,
                                            uint32_t* capacity,
                                            OrenAVMMetalTriangleOrder** heapStorage,
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
        if ((NSUInteger)newCapacity > NSUIntegerMax / sizeof(OrenAVMMetalTriangleOrder)) return NO;
        OrenAVMMetalTriangleOrder* grown = NULL;
        if (*heapStorage) {
            grown = (OrenAVMMetalTriangleOrder*)realloc(*heapStorage, (NSUInteger)newCapacity * sizeof(OrenAVMMetalTriangleOrder));
        } else {
            grown = (OrenAVMMetalTriangleOrder*)malloc((NSUInteger)newCapacity * sizeof(OrenAVMMetalTriangleOrder));
            if (grown && inlineOrder && *count != 0) {
                memcpy(grown, inlineOrder, (NSUInteger)*count * sizeof(OrenAVMMetalTriangleOrder));
            }
        }
        if (!grown) return NO;
        *heapStorage = grown;
        *order = grown;
        *capacity = newCapacity;
    }
    (*order)[*count] = (OrenAVMMetalTriangleOrder){triangle, zsum};
    *count += 1u;
    return YES;
}

int64_t OrenAVMMetalMesh3DIndexedZSumModel(const uint8_t* vertices,
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

float OrenAVMMetalMesh3DModelCoord(const uint8_t* p, int32_t offset, uint32_t scaleMilli) {
    int32_t v = (int32_t)OrenAVMMetalReadU32LE(p);
    return (float)(((int64_t)v * (int64_t)scaleMilli) / 1000 + (int64_t)offset);
}

uint8_t* OrenAVMMetalCopyPayloadBytes(const uint8_t* src, NSUInteger len) {
    if (!src || len == 0) return NULL;
    uint8_t* out = (uint8_t*)malloc(len);
    if (!out) return NULL;
    memcpy(out, src, len);
    return out;
}

#endif
