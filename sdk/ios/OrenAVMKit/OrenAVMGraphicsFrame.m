#import "OrenAVMGraphicsFrame.h"

#if TARGET_OS_IPHONE

#import "OrenAVMGraphicsGeometry.h"
#import "OrenAVMGraphicsResources.h"
#include <string.h>

BOOL OrenAVMGfxFrameDataIsValid(NSData* frame) {
    if (frame.length < 24) return NO;
    const uint8_t* data = (const uint8_t*)frame.bytes;
    if (memcmp(data, "OGF0", 4) != 0) return NO;
    uint8_t version = data[4];
    if (version != 0 && version != 1) return NO;
    uint16_t headerLen = version == 0 ? 24 : OrenAVMGfxReadU16LE(data + 6);
    if (headerLen < 24 || headerLen > frame.length) return NO;
    return OrenAVMGfxReadU32LE(data + 8) != 0 && OrenAVMGfxReadU32LE(data + 12) != 0;
}

void OrenAVMGfxFrameStateInit(OrenAVMGfxFrameState* state) {
    if (!state) return;
    memset(state, 0, sizeof(*state));
    state->opacity = 1.0;
}

void OrenAVMGfxDrawFrame(CGContextRef ctx, NSData* frame, OrenAVMGfxFrameDrawContext* context) {
    if (!ctx || !context || !OrenAVMGfxFrameDataIsValid(frame)) return;
    const uint8_t* data = (const uint8_t*)frame.bytes;
    uint8_t version = data[4];
    uint16_t headerLen = version == 0 ? 24 : OrenAVMGfxReadU16LE(data + 6);
    if (headerLen < 24 || headerLen > frame.length) return;
    uint32_t width = OrenAVMGfxReadU32LE(data + 8);
    uint32_t height = OrenAVMGfxReadU32LE(data + 12);
    uint32_t opCount = OrenAVMGfxReadU32LE(data + 20);
    if (width == 0 || height == 0) return;

    size_t off = headerLen;
    size_t len = frame.length;
    OrenAVMGfxFrameState frameState;
    OrenAVMGfxFrameStateInit(&frameState);
    for (uint32_t i = 0; i < opCount && off + 4 <= len; i++) {
        uint8_t opcode = data[off];
        uint16_t payloadLen = OrenAVMGfxReadU16LE(data + off + 2);
        off += 4;
        if (off + (size_t)payloadLen > len) return;
        const uint8_t* payload = data + off;

        if (OrenAVMGfxDrawImmediatePrimitive(ctx, opcode, payload, payloadLen)) {
            off += payloadLen;
            continue;
        }
        if (OrenAVMGfxHandleFrameStateCommand(ctx, opcode, payload, payloadLen, &frameState)) {
            off += payloadLen;
            continue;
        }

        if (OrenAVMGfxHandleMeshCommand(ctx,
                                        context->meshes,
                                        context->materials3D,
                                        context->models3D,
                                        opcode,
                                        payload,
                                        payloadLen,
                                        frameState.depthEnabled,
                                        frameState.nearZ,
                                        frameState.farZ) ||
            OrenAVMGfxHandleTextCommand(ctx,
                                        context->textAttributes,
                                        context->lastTextAttributesRGBA,
                                        context->lastTextAttributes,
                                        context->textResources,
                                        opcode,
                                        payload,
                                        payloadLen) ||
            OrenAVMGfxHandleImageCommand(ctx,
                                         context->images,
                                         context->retainedImageCountLimit,
                                         context->retainedImagePixelLimit,
                                         context->retainedImagePixelCount,
                                         opcode,
                                         payload,
                                         payloadLen)) {
            off += payloadLen;
            continue;
        }

        off += payloadLen;
    }
    OrenAVMGfxRestoreFrameState(ctx, &frameState);
}

BOOL OrenAVMGfxHandleFrameStateCommand(CGContextRef ctx,
                                       uint8_t opcode,
                                       const uint8_t* payload,
                                       uint16_t payloadLen,
                                       OrenAVMGfxFrameState* state) {
    if (!ctx || !payload || !state) return NO;
    switch (opcode) {
        case 16: {
            if (payloadLen == 16) {
                uint32_t x = OrenAVMGfxReadU32LE(payload);
                uint32_t y = OrenAVMGfxReadU32LE(payload + 4);
                uint32_t w = OrenAVMGfxReadU32LE(payload + 8);
                uint32_t h = OrenAVMGfxReadU32LE(payload + 12);
                CGContextSaveGState(ctx);
                CGContextClipToRect(ctx, CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h));
                state->clipDepth++;
                state->stateDepth++;
            }
            return YES;
        }
        case 17: {
            if (payloadLen == 0 && state->clipDepth > 0) {
                CGContextRestoreGState(ctx);
                state->clipDepth--;
                if (state->stateDepth > 0) state->stateDepth--;
            }
            return YES;
        }
        case 18: {
            if (payloadLen == 8) {
                int32_t dx = (int32_t)OrenAVMGfxReadU32LE(payload);
                int32_t dy = (int32_t)OrenAVMGfxReadU32LE(payload + 4);
                CGContextSaveGState(ctx);
                CGContextTranslateCTM(ctx, (CGFloat)dx, (CGFloat)dy);
                state->stateDepth++;
            }
            return YES;
        }
        case 19: {
            if (payloadLen == 0 && state->stateDepth > 0) {
                CGContextRestoreGState(ctx);
                state->stateDepth--;
            }
            return YES;
        }
        case 20: {
            if (payloadLen == 4) {
                uint32_t alphaMilli = OrenAVMGfxReadU32LE(payload);
                if (state->opacityDepth < 64) {
                    state->opacityStack[state->opacityDepth++] = state->opacity;
                    state->opacity = state->opacity * ((CGFloat)alphaMilli / 1000.0);
                    CGContextSaveGState(ctx);
                    CGContextSetAlpha(ctx, state->opacity);
                    state->stateDepth++;
                } else {
                    state->opacityOverflowDepth++;
                }
            }
            return YES;
        }
        case 21: {
            if (payloadLen == 0) {
                if (state->opacityOverflowDepth > 0) {
                    state->opacityOverflowDepth--;
                } else if (state->opacityDepth > 0 && state->stateDepth > 0) {
                    CGContextRestoreGState(ctx);
                    state->opacity = state->opacityStack[--state->opacityDepth];
                    state->stateDepth--;
                }
            }
            return YES;
        }
        case 22: {
            if (payloadLen == 8) {
                if (state->cameraDepth < 64) {
                    state->depthEnabledStack[state->cameraDepth] = state->depthEnabled;
                    state->nearZStack[state->cameraDepth] = state->nearZ;
                    state->farZStack[state->cameraDepth] = state->farZ;
                    state->cameraDepth++;
                    state->depthEnabled = YES;
                    state->nearZ = (int32_t)OrenAVMGfxReadU32LE(payload);
                    state->farZ = (int32_t)OrenAVMGfxReadU32LE(payload + 4);
                } else {
                    state->cameraOverflowDepth++;
                }
            }
            return YES;
        }
        case 23: {
            if (payloadLen == 0) {
                if (state->cameraOverflowDepth > 0) {
                    state->cameraOverflowDepth--;
                } else if (state->cameraDepth > 0) {
                    state->cameraDepth--;
                    state->depthEnabled = state->depthEnabledStack[state->cameraDepth];
                    state->nearZ = state->nearZStack[state->cameraDepth];
                    state->farZ = state->farZStack[state->cameraDepth];
                }
            }
            return YES;
        }
        default:
            return NO;
    }
}

void OrenAVMGfxRestoreFrameState(CGContextRef ctx, OrenAVMGfxFrameState* state) {
    if (!ctx || !state) return;
    while (state->stateDepth > 0) {
        CGContextRestoreGState(ctx);
        state->stateDepth--;
    }
}

#endif
