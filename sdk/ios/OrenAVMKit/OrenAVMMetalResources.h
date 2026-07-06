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

uint8_t* OrenAVMMetalCopyPayloadBytes(const uint8_t* src, NSUInteger len);

#endif
