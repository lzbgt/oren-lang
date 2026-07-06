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
    resource.texture = texture;
    resource.pixels = pixels;
    if (!*imagesByID) *imagesByID = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!*imagesByID) return NO;
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
    run.texture = texture;
    OrenAVMMetalWriteTextureQuad(run->vertices, x, y, w, h, logicalWidth, logicalHeight, u0, v0, u1, v1);
    run.opacity = opacity;
    return run;
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
                                 NSString* text) {
    if (!texts || textID == 0 || !text) return NO;
    OrenAVMMetalTextResource* resource = [[OrenAVMMetalTextResource alloc] init];
    resource.text = text;
    resource.rgbaValue = rgbaValue;
    if (!*texts) *texts = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!*texts) return NO;
    CFDictionarySetValue(*texts, OrenAVMMetalRetainedTextKey(textID), (__bridge const void*)resource);
    return YES;
}

void OrenAVMMetalRemoveTextResource(CFMutableDictionaryRef texts, uint32_t textID) {
    if (texts && textID != 0) CFDictionaryRemoveValue(texts, OrenAVMMetalRetainedTextKey(textID));
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

void OrenAVMMetalAppendMesh2DResource(OrenAVMMetalMesh2DResource* mesh,
                                      OrenAVMMetalVertexBuffer* vertices,
                                      float tx,
                                      float ty,
                                      float logicalWidth,
                                      float logicalHeight,
                                      float opacity) {
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

BOOL OrenAVMMetalPutMesh2DResource(CFMutableDictionaryRef* meshes,
                                   uint32_t meshID,
                                   uint32_t rgbaValue,
                                   const uint8_t* triangles,
                                   NSUInteger triangleBytes,
                                   uint32_t triangleCount) {
    if (!meshes || meshID == 0 || !triangles || triangleBytes == 0) return NO;
    OrenAVMMetalMesh2DResource* mesh = [[OrenAVMMetalMesh2DResource alloc] init];
    mesh.rgbaValue = rgbaValue;
    mesh.triangleBytes = triangleBytes;
    mesh.triangles = OrenAVMMetalCopyPayloadBytes(triangles, triangleBytes);
    if (!mesh.triangles) return NO;
    mesh.triangleCount = triangleCount;
    if (!*meshes) *meshes = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!*meshes) return NO;
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
    OrenAVMMetalMesh3DResource* mesh = [[OrenAVMMetalMesh3DResource alloc] init];
    mesh.rgbaValue = rgbaValue;
    mesh.hasRGBA = hasRGBA;
    mesh.triangleBytes = triangleBytes;
    mesh.triangles = OrenAVMMetalCopyPayloadBytes(triangles, triangleBytes);
    if (!mesh.triangles) return NO;
    mesh.triangleCount = triangleCount;
    mesh.stride = stride;
    if (!*meshes) *meshes = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!*meshes) return NO;
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
    OrenAVMMetalMesh3DResource* mesh = [[OrenAVMMetalMesh3DResource alloc] init];
    mesh.rgbaValue = rgbaValue;
    mesh.hasRGBA = YES;
    mesh.vertexBytes = vertexBytes;
    mesh.indexBytes = indexBytes;
    mesh.vertices = OrenAVMMetalCopyPayloadBytes(vertices, vertexBytes);
    mesh.indices = OrenAVMMetalCopyPayloadBytes(indices, indexBytes);
    if (!mesh.vertices || !mesh.indices) return NO;
    mesh.indexCount = indexCount;
    if (!*meshes) *meshes = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!*meshes) return NO;
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
    if (!*materials) *materials = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    if (!*materials) return NO;
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
    OrenAVMMetalModelResource* model = [[OrenAVMMetalModelResource alloc] init];
    model.meshID = meshID;
    model.materialID = materialID;
    model.x = x;
    model.y = y;
    model.z = z;
    model.scaleMilli = scaleMilli;
    if (!*models) *models = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    if (!*models) return NO;
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

OrenAVMMetalTriangleOrder* OrenAVMMetalTriangleOrderBuffer(uint32_t triangleCount,
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

void OrenAVMMetalSortTriangleOrder(OrenAVMMetalTriangleOrder* order, uint32_t count) {
    if (count > 1) qsort(order, count, sizeof(OrenAVMMetalTriangleOrder), OrenAVMMetalTriangleOrderCompare);
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
    if (len == 0) return NULL;
    uint8_t* out = (uint8_t*)malloc(len);
    if (!out) return NULL;
    memcpy(out, src, len);
    return out;
}

#endif
