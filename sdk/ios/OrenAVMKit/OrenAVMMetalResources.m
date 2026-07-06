#import "OrenAVMMetalResources.h"

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

const void* OrenAVMMetalRetainedTextKey(uint32_t textID) {
    return OrenAVMMetalRetainedKey(textID);
}

OrenAVMMetalTextResource* OrenAVMMetalRetainedTextResource(CFDictionaryRef texts, uint32_t textID) {
    if (!texts || textID == 0) return nil;
    return (__bridge OrenAVMMetalTextResource*)CFDictionaryGetValue(texts, OrenAVMMetalRetainedTextKey(textID));
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

const void* OrenAVMMetalRetainedModelKey(uint32_t modelID) {
    return OrenAVMMetalRetainedKey(modelID);
}

OrenAVMMetalModelResource* OrenAVMMetalRetainedModelResource(CFDictionaryRef models, uint32_t modelID) {
    if (!models || modelID == 0) return nil;
    return (__bridge OrenAVMMetalModelResource*)CFDictionaryGetValue(models, OrenAVMMetalRetainedModelKey(modelID));
}

uint8_t* OrenAVMMetalCopyPayloadBytes(const uint8_t* src, NSUInteger len) {
    if (len == 0) return NULL;
    uint8_t* out = (uint8_t*)malloc(len);
    if (!out) return NULL;
    memcpy(out, src, len);
    return out;
}

#endif
