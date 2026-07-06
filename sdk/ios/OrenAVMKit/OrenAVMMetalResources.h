#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <Metal/Metal.h>
#import "OrenAVMMetalGeometry.h"
#import "OrenAVMMetalText.h"
#include <stdint.h>

typedef struct {
    uint32_t triangle;
    int64_t zsum;
} OrenAVMMetalTriangleOrder;

enum { OrenAVMMetalInlineTriangleOrderCapacity = 128 };

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
BOOL OrenAVMMetalPutImageResource(CFMutableDictionaryRef* imagesByID,
                                  id<MTLDevice> device,
                                  uint32_t imageID,
                                  uint32_t width,
                                  uint32_t height,
                                  const uint8_t* rgba,
                                  uint32_t byteCount,
                                  NSUInteger retainedImageCountLimit,
                                  NSUInteger retainedImagePixelLimit,
                                  NSUInteger* retainedImagePixelCount);
void OrenAVMMetalRemoveImageResource(CFMutableDictionaryRef imagesByID,
                                     uint32_t imageID,
                                     NSUInteger* retainedImagePixelCount);
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
                                                 float logicalHeight);
const void* OrenAVMMetalRetainedTextKey(uint32_t textID);
OrenAVMMetalTextResource* OrenAVMMetalRetainedTextResource(CFDictionaryRef texts, uint32_t textID);
BOOL OrenAVMMetalPutTextResource(CFMutableDictionaryRef* texts,
                                 uint32_t textID,
                                 uint32_t rgbaValue,
                                 NSString* text);
void OrenAVMMetalRemoveTextResource(CFMutableDictionaryRef texts, uint32_t textID);
const void* OrenAVMMetalRetainedMeshKey(uint32_t meshID);
OrenAVMMetalMesh2DResource* OrenAVMMetalRetainedMesh2DResource(CFDictionaryRef meshes, uint32_t meshID);
OrenAVMMetalMesh3DResource* OrenAVMMetalRetainedMesh3DResource(CFDictionaryRef meshes, uint32_t meshID);
void OrenAVMMetalAppendMesh2DResource(OrenAVMMetalMesh2DResource* mesh,
                                      OrenAVMMetalVertexBuffer* vertices,
                                      float tx,
                                      float ty,
                                      float logicalWidth,
                                      float logicalHeight,
                                      float opacity);
BOOL OrenAVMMetalPutMesh2DResource(CFMutableDictionaryRef* meshes,
                                   uint32_t meshID,
                                   uint32_t rgbaValue,
                                   const uint8_t* triangles,
                                   NSUInteger triangleBytes,
                                   uint32_t triangleCount);
void OrenAVMMetalRemoveMeshResource(CFMutableDictionaryRef meshes, uint32_t meshID);
BOOL OrenAVMMetalPutPackedMesh3DResource(CFMutableDictionaryRef* meshes,
                                         uint32_t meshID,
                                         uint32_t rgbaValue,
                                         BOOL hasRGBA,
                                         const uint8_t* triangles,
                                         NSUInteger triangleBytes,
                                         uint32_t triangleCount,
                                         uint32_t stride);
BOOL OrenAVMMetalPutIndexedMesh3DResource(CFMutableDictionaryRef* meshes,
                                          uint32_t meshID,
                                          uint32_t rgbaValue,
                                          const uint8_t* vertices,
                                          NSUInteger vertexBytes,
                                          const uint8_t* indices,
                                          NSUInteger indexBytes,
                                          uint32_t indexCount);
const void* OrenAVMMetalRetainedMaterialKey(uint32_t materialID);
const void* OrenAVMMetalRetainedMaterialValue(uint32_t rgbaValue);
BOOL OrenAVMMetalRetainedMaterialRGBA(CFDictionaryRef materials, uint32_t materialID, uint32_t* rgbaOut);
BOOL OrenAVMMetalPutMaterialResource(CFMutableDictionaryRef* materials, uint32_t materialID, uint32_t rgbaValue);
void OrenAVMMetalRemoveMaterialResource(CFMutableDictionaryRef materials, uint32_t materialID);
const void* OrenAVMMetalRetainedModelKey(uint32_t modelID);
OrenAVMMetalModelResource* OrenAVMMetalRetainedModelResource(CFDictionaryRef models, uint32_t modelID);
BOOL OrenAVMMetalPutModelResource(CFMutableDictionaryRef* models,
                                  uint32_t modelID,
                                  uint32_t meshID,
                                  uint32_t materialID,
                                  int32_t x,
                                  int32_t y,
                                  int32_t z,
                                  uint32_t scaleMilli);
void OrenAVMMetalRemoveModelResource(CFMutableDictionaryRef models, uint32_t modelID);

int64_t OrenAVMMetalMesh3DZSumModel(const uint8_t* tri, int32_t offset, uint32_t scaleMilli);
BOOL OrenAVMMetalMesh3DZVisible(int64_t zsum, BOOL depthEnabled, int32_t nearZ, int32_t farZ);
OrenAVMMetalTriangleOrder* OrenAVMMetalTriangleOrderBuffer(uint32_t triangleCount,
                                                           OrenAVMMetalTriangleOrder* inlineOrder,
                                                           uint32_t inlineCapacity,
                                                           OrenAVMMetalTriangleOrder** heapStorage);
void OrenAVMMetalSortTriangleOrder(OrenAVMMetalTriangleOrder* order, uint32_t count);
int64_t OrenAVMMetalMesh3DIndexedZSumModel(const uint8_t* vertices,
                                           const uint8_t* indices,
                                           uint32_t triangle,
                                           int32_t offset,
                                           uint32_t scaleMilli);
float OrenAVMMetalMesh3DModelCoord(const uint8_t* p, int32_t offset, uint32_t scaleMilli);

uint8_t* OrenAVMMetalCopyPayloadBytes(const uint8_t* src, NSUInteger len);

#endif
