#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <Metal/Metal.h>
#import "OrenAVMMetalText.h"
#include <stdint.h>

@interface OrenAVMMetalVertexRun : NSObject
@property(nonatomic) uint8_t* vertices;
@property(nonatomic) NSUInteger vertexBytes;
@property(nonatomic) BOOL hasScissor;
@property(nonatomic) MTLScissorRect scissor;
@end

@interface OrenAVMMetalImageRun : NSObject {
@public
    OrenAVMMetalTextVertex vertices[6];
}
@property(nonatomic, strong) id<MTLTexture> texture;
@property(nonatomic) BOOL hasScissor;
@property(nonatomic) MTLScissorRect scissor;
@property(nonatomic) float opacity;
@end

@interface OrenAVMMetalImageResource : NSObject
@property(nonatomic, strong) id<MTLTexture> texture;
@property(nonatomic) NSUInteger pixels;
@end

@interface OrenAVMMetalMesh2DResource : NSObject
@property(nonatomic) uint8_t* triangles;
@property(nonatomic) NSUInteger triangleBytes;
@property(nonatomic) uint32_t rgbaValue;
@property(nonatomic) uint32_t triangleCount;
@end

@interface OrenAVMMetalMesh3DResource : NSObject
@property(nonatomic) uint8_t* triangles;
@property(nonatomic) NSUInteger triangleBytes;
@property(nonatomic) uint8_t* vertices;
@property(nonatomic) NSUInteger vertexBytes;
@property(nonatomic) uint8_t* indices;
@property(nonatomic) NSUInteger indexBytes;
@property(nonatomic) uint32_t rgbaValue;
@property(nonatomic) BOOL hasRGBA;
@property(nonatomic) uint32_t triangleCount;
@property(nonatomic) uint32_t indexCount;
@property(nonatomic) uint32_t stride;
@end

@interface OrenAVMMetalModelResource : NSObject
@property(nonatomic) uint32_t meshID;
@property(nonatomic) uint32_t materialID;
@property(nonatomic) int32_t x;
@property(nonatomic) int32_t y;
@property(nonatomic) int32_t z;
@property(nonatomic) uint32_t scaleMilli;
@end

const void* OrenAVMMetalRetainedImageKey(uint32_t imageID);
OrenAVMMetalImageResource* OrenAVMMetalRetainedImageResource(CFDictionaryRef images, uint32_t imageID);
const void* OrenAVMMetalRetainedTextKey(uint32_t textID);
OrenAVMMetalTextResource* OrenAVMMetalRetainedTextResource(CFDictionaryRef texts, uint32_t textID);
const void* OrenAVMMetalRetainedMeshKey(uint32_t meshID);
OrenAVMMetalMesh2DResource* OrenAVMMetalRetainedMesh2DResource(CFDictionaryRef meshes, uint32_t meshID);
OrenAVMMetalMesh3DResource* OrenAVMMetalRetainedMesh3DResource(CFDictionaryRef meshes, uint32_t meshID);
const void* OrenAVMMetalRetainedMaterialKey(uint32_t materialID);
const void* OrenAVMMetalRetainedMaterialValue(uint32_t rgbaValue);
BOOL OrenAVMMetalRetainedMaterialRGBA(CFDictionaryRef materials, uint32_t materialID, uint32_t* rgbaOut);
const void* OrenAVMMetalRetainedModelKey(uint32_t modelID);
OrenAVMMetalModelResource* OrenAVMMetalRetainedModelResource(CFDictionaryRef models, uint32_t modelID);

uint8_t* OrenAVMMetalCopyPayloadBytes(const uint8_t* src, NSUInteger len);

#endif
