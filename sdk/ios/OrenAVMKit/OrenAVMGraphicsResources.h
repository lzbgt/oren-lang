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
const void* OrenAVMGfxRetainedTextKey(uint32_t textID);
OrenAVMGfxTextResource* OrenAVMGfxRetainedTextResource(CFDictionaryRef texts, uint32_t textID);
const void* OrenAVMGfxRetainedMeshKey(uint32_t meshID);
OrenAVMGfxMeshResource* OrenAVMGfxRetainedMeshResource(CFDictionaryRef meshes, uint32_t meshID);
const void* OrenAVMGfxRetainedMaterialKey(uint32_t materialID);
const void* OrenAVMGfxRetainedMaterialValue(uint32_t rgbaValue);
BOOL OrenAVMGfxRetainedMaterialRGBA(CFDictionaryRef materials, uint32_t materialID, uint32_t* rgbaOut);
const void* OrenAVMGfxRetainedModelKey(uint32_t modelID);
OrenAVMGfxModelResource* OrenAVMGfxRetainedModelResource(CFDictionaryRef models, uint32_t modelID);

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
