#import "OrenAVMGraphicsResources.h"

#if TARGET_OS_IPHONE

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

const void* OrenAVMGfxRetainedTextKey(uint32_t textID) {
    return OrenAVMGfxRetainedKey(textID);
}

OrenAVMGfxTextResource* OrenAVMGfxRetainedTextResource(CFDictionaryRef texts, uint32_t textID) {
    if (!texts || textID == 0) return nil;
    return (__bridge OrenAVMGfxTextResource*)CFDictionaryGetValue(texts, OrenAVMGfxRetainedTextKey(textID));
}

const void* OrenAVMGfxRetainedMeshKey(uint32_t meshID) {
    return OrenAVMGfxRetainedKey(meshID);
}

OrenAVMGfxMeshResource* OrenAVMGfxRetainedMeshResource(CFDictionaryRef meshes, uint32_t meshID) {
    if (!meshes || meshID == 0) return nil;
    return (__bridge OrenAVMGfxMeshResource*)CFDictionaryGetValue(meshes, OrenAVMGfxRetainedMeshKey(meshID));
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

const void* OrenAVMGfxRetainedModelKey(uint32_t modelID) {
    return OrenAVMGfxRetainedKey(modelID);
}

OrenAVMGfxModelResource* OrenAVMGfxRetainedModelResource(CFDictionaryRef models, uint32_t modelID) {
    if (!models || modelID == 0) return nil;
    return (__bridge OrenAVMGfxModelResource*)CFDictionaryGetValue(models, OrenAVMGfxRetainedModelKey(modelID));
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
