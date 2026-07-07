#pragma once

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <UIKit/UIKit.h>
#include <stdint.h>

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

@interface OrenAVMGfxTextResource : NSObject
@property(nonatomic, strong) NSAttributedString* attributedText;
@end

@interface OrenAVMGfxImageResource : NSObject
@property(nonatomic, strong) UIImage* image;
@property(nonatomic) NSUInteger pixels;
@end

@interface OrenAVMGfxModelResource : NSObject
@property(nonatomic) uint32_t meshID;
@property(nonatomic) uint32_t materialID;
@property(nonatomic) int32_t x;
@property(nonatomic) int32_t y;
@property(nonatomic) int32_t z;
@property(nonatomic) uint32_t scaleMilli;
@end

const void* OrenAVMGfxRetainedImageKey(uint32_t imageID);
OrenAVMGfxImageResource* OrenAVMGfxRetainedImageResource(CFDictionaryRef images, uint32_t imageID);
UIImage* OrenAVMGfxImageRGBA(const uint8_t* rgba, uint32_t width, uint32_t height, uint32_t byteCount);
BOOL OrenAVMGfxPutImageResource(CFMutableDictionaryRef* imagesByID,
                                UIImage* image,
                                uint32_t imageID,
                                NSUInteger pixels,
                                NSUInteger retainedImageCountLimit,
                                NSUInteger retainedImagePixelLimit,
                                NSUInteger* retainedImagePixelCount);
void OrenAVMGfxRemoveImageResource(CFMutableDictionaryRef imagesByID,
                                   uint32_t imageID,
                                   NSUInteger* retainedImagePixelCount);
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
                                uint32_t h);
const void* OrenAVMGfxRetainedTextKey(uint32_t textID);
OrenAVMGfxTextResource* OrenAVMGfxRetainedTextResource(CFDictionaryRef texts, uint32_t textID);
NSDictionary<NSAttributedStringKey, id>* OrenAVMGfxTextAttributesForRGBA(CFMutableDictionaryRef* attrsByRGBA,
                                                                         uint32_t* lastRGBA,
                                                                         NSDictionary<NSAttributedStringKey, id>* __strong* lastAttributes,
                                                                         uint32_t rgbaValue);
void OrenAVMGfxDrawTextBytes(const uint8_t* textBytes,
                             uint32_t textLen,
                             uint32_t x,
                             uint32_t y,
                             NSDictionary<NSAttributedStringKey, id>* attrs);
BOOL OrenAVMGfxPutTextResource(CFMutableDictionaryRef* texts,
                               uint32_t textID,
                               const uint8_t* textBytes,
                               uint32_t textLen,
                               NSDictionary<NSAttributedStringKey, id>* attrs);
void OrenAVMGfxDrawTextResource(CFDictionaryRef texts, uint32_t textID, uint32_t x, uint32_t y);
void OrenAVMGfxDrawTextResourcePositions(CFDictionaryRef texts,
                                         uint32_t textID,
                                         const uint8_t* positions,
                                         uint32_t posCount);
void OrenAVMGfxRemoveTextResource(CFMutableDictionaryRef texts, uint32_t textID);
const void* OrenAVMGfxRetainedMeshKey(uint32_t meshID);
OrenAVMGfxMeshResource* OrenAVMGfxRetainedMeshResource(CFDictionaryRef meshes, uint32_t meshID);
BOOL OrenAVMGfxPutTriangleMeshResource(CFMutableDictionaryRef* meshes,
                                       uint32_t meshID,
                                       uint32_t rgbaValue,
                                       const uint8_t* triangles,
                                       NSUInteger triangleBytes,
                                       uint32_t triangleCount,
                                       uint32_t stride,
                                       BOOL hasRGBA);
BOOL OrenAVMGfxPutIndexedMeshResource(CFMutableDictionaryRef* meshes,
                                      uint32_t meshID,
                                      uint32_t rgbaValue,
                                      const uint8_t* vertices,
                                      NSUInteger vertexBytes,
                                      uint32_t vertexCount,
                                      const uint8_t* indices,
                                      NSUInteger indexBytes,
                                      uint32_t indexCount);
void OrenAVMGfxRemoveMeshResource(CFMutableDictionaryRef meshes, uint32_t meshID);
const void* OrenAVMGfxRetainedMaterialKey(uint32_t materialID);
const void* OrenAVMGfxRetainedMaterialValue(uint32_t rgbaValue);
BOOL OrenAVMGfxRetainedMaterialRGBA(CFDictionaryRef materials, uint32_t materialID, uint32_t* rgbaOut);
BOOL OrenAVMGfxPutMaterialResource(CFMutableDictionaryRef* materials, uint32_t materialID, uint32_t rgbaValue);
void OrenAVMGfxRemoveMaterialResource(CFMutableDictionaryRef materials, uint32_t materialID);
const void* OrenAVMGfxRetainedModelKey(uint32_t modelID);
OrenAVMGfxModelResource* OrenAVMGfxRetainedModelResource(CFDictionaryRef models, uint32_t modelID);
BOOL OrenAVMGfxPutModelResource(CFMutableDictionaryRef* models,
                                uint32_t modelID,
                                uint32_t meshID,
                                uint32_t materialID,
                                int32_t x,
                                int32_t y,
                                int32_t z,
                                uint32_t scaleMilli);
void OrenAVMGfxRemoveModelResource(CFMutableDictionaryRef models, uint32_t modelID);

uint8_t* OrenAVMGfxCopyPayloadBytes(const uint8_t* src, NSUInteger len);
int64_t OrenAVMGfxMesh3DZSumModel(const uint8_t* tri, int32_t offset, uint32_t scaleMilli);
BOOL OrenAVMGfxMesh3DZVisible(int64_t zsum, BOOL depthEnabled, int32_t nearZ, int32_t farZ);
OrenAVMGfxTriangleOrder* OrenAVMGfxTriangleOrderBuffer(uint32_t triangleCount,
                                                       OrenAVMGfxTriangleOrder* inlineOrder,
                                                       uint32_t inlineCapacity,
                                                       OrenAVMGfxTriangleOrder** heapStorage);
void OrenAVMGfxSortTriangleOrder(OrenAVMGfxTriangleOrder* order, uint32_t count);
int64_t OrenAVMGfxMesh3DIndexedZSumModel(const uint8_t* vertices,
                                         const uint8_t* indices,
                                         uint32_t triangle,
                                         int32_t offset,
                                         uint32_t scaleMilli);
CGFloat OrenAVMGfxMesh3DModelCoord(const uint8_t* p, int32_t offset, uint32_t scaleMilli);

#endif
