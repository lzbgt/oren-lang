#pragma once

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE

#import <UIKit/UIKit.h>
#include <stdint.h>

typedef struct {
    uint32_t clipDepth;
    uint32_t stateDepth;
    CGFloat opacity;
    CGFloat opacityStack[64];
    uint32_t opacityDepth;
    BOOL depthEnabled;
    int32_t nearZ;
    int32_t farZ;
    BOOL depthEnabledStack[64];
    int32_t nearZStack[64];
    int32_t farZStack[64];
    uint32_t cameraDepth;
} OrenAVMGfxFrameState;

static inline uint16_t OrenAVMGfxReadU16LE(const uint8_t* p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static inline uint32_t OrenAVMGfxReadU32LE(const uint8_t* p) {
    return (uint32_t)p[0] |
        ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) |
        ((uint32_t)p[3] << 24);
}

BOOL OrenAVMGfxFrameDataIsValid(NSData* frame);
void OrenAVMGfxFrameStateInit(OrenAVMGfxFrameState* state);
BOOL OrenAVMGfxHandleFrameStateCommand(CGContextRef ctx,
                                       uint8_t opcode,
                                       const uint8_t* payload,
                                       uint16_t payloadLen,
                                       OrenAVMGfxFrameState* state);
void OrenAVMGfxRestoreFrameState(CGContextRef ctx, OrenAVMGfxFrameState* state);

#endif
