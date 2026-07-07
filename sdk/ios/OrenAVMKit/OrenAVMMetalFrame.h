#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <Metal/Metal.h>
#import "OrenAVMMetalGeometry.h"
#import "OrenAVMMetalResources.h"
#include <stdint.h>

typedef struct {
    BOOL enabled;
    MTLScissorRect rect;
} OrenAVMMetalScissorState;

typedef struct {
    OrenAVMMetalScissorState clip;
    OrenAVMMetalScissorState clipStack[64];
    uint32_t clipDepth;
    float tx;
    float ty;
    float txStack[64];
    float tyStack[64];
    uint32_t transformDepth;
    float opacity;
    float opacityStack[64];
    uint32_t opacityDepth;
    BOOL depthEnabled;
    int32_t nearZ;
    int32_t farZ;
    BOOL depthEnabledStack[64];
    int32_t nearZStack[64];
    int32_t farZStack[64];
    uint32_t cameraDepth;
} OrenAVMMetalFrameState;

static const NSUInteger OrenAVMMetalInlineVertexBytesLimit = 4096u;

static inline uint16_t OrenAVMMetalReadU16LE(const uint8_t* p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static inline uint32_t OrenAVMMetalReadU32LE(const uint8_t* p) {
    return (uint32_t)p[0] |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static inline BOOL OrenAVMMetalSubrectInTexture(uint32_t sx, uint32_t sy, uint32_t sw, uint32_t sh, NSUInteger width, NSUInteger height) {
    return (uint64_t)sx + (uint64_t)sw <= (uint64_t)width &&
        (uint64_t)sy + (uint64_t)sh <= (uint64_t)height;
}

BOOL OrenAVMMetalFrameDataIsValid(NSData* frame);
NSUInteger OrenAVMMetalFrameRunCapacity(NSData* frame);
NSMutableArray* OrenAVMMetalEnsureRunArray(NSMutableArray** runs, NSUInteger capacity);
uint64_t OrenAVMMetalNowNs(void);
uint64_t OrenAVMMetalTargetBudgetNs(uint32_t hzMilli);
void OrenAVMMetalFrameStateInit(OrenAVMMetalFrameState* state);
BOOL OrenAVMMetalApplyClearColorCommand(uint8_t opcode,
                                        const uint8_t* payload,
                                        uint16_t payloadLen,
                                        uint32_t logicalW,
                                        uint32_t logicalH,
                                        float opacity,
                                        MTLClearColor* clearColor);
BOOL OrenAVMMetalHandleFrameStateCommand(uint8_t opcode,
                                         const uint8_t* payload,
                                         uint16_t payloadLen,
                                         NSMutableArray<OrenAVMMetalVertexRun*>** runsRef,
                                         OrenAVMMetalVertexBuffer* verticesRef,
                                         NSUInteger runCapacity,
                                         OrenAVMMetalFrameState* state,
                                         uint32_t logicalW,
                                         uint32_t logicalH,
                                         uint32_t drawableW,
                                         uint32_t drawableH);

MTLScissorRect OrenAVMMetalClipRectToScissor(int64_t x,
                                             int64_t y,
                                             uint32_t w,
                                             uint32_t h,
                                             uint32_t logicalW,
                                             uint32_t logicalH,
                                             uint32_t drawableW,
                                             uint32_t drawableH);
MTLScissorRect OrenAVMMetalIntersectScissor(MTLScissorRect a, MTLScissorRect b);

NSUInteger OrenAVMMetalInitialVertexBuilderCapacity(NSUInteger runCapacity);
OrenAVMMetalVertexBuffer* OrenAVMMetalEnsureVertexBuilder(OrenAVMMetalVertexBuffer* vertices, NSUInteger runCapacity);
void OrenAVMMetalFlushVertexRun(NSMutableArray<OrenAVMMetalVertexRun*>** runsRef,
                                OrenAVMMetalVertexBuffer* verticesRef,
                                NSUInteger runCapacity,
                                OrenAVMMetalScissorState scissor,
                                BOOL continueBuilding);
BOOL OrenAVMMetalBindVertexPayload(id<MTLRenderCommandEncoder> encoder,
                                   id<MTLDevice> device,
                                   NSMutableArray<id<MTLBuffer>>** transientBuffers,
                                   const void* bytes,
                                   NSUInteger length);
void OrenAVMMetalEncodePreparedRuns(id<MTLRenderCommandEncoder> encoder,
                                    id<MTLDevice> device,
                                    id<MTLRenderPipelineState> geometryPipeline,
                                    id<MTLRenderPipelineState> textPipeline,
                                    id<MTLTexture> drawableTexture,
                                    NSArray<OrenAVMMetalVertexRun*>* vertexRuns,
                                    NSArray<OrenAVMMetalImageRun*>* imageRuns,
                                    NSArray<OrenAVMMetalTextRun*>* textRuns,
                                    NSMutableArray<id<MTLBuffer>>** transientBuffers);

#endif
