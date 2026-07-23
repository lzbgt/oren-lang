#import "OrenAVMGraphicsFrame.h"

#if TARGET_OS_IPHONE

#import "OrenAVMGraphicsGeometry.h"
#import "OrenAVMGraphicsResources.h"
#include <string.h>

typedef uint8_t OrenAVMGfxStateKind;
enum {
    OrenAVMGfxStateKindClip = 1,
    OrenAVMGfxStateKindTransform = 2,
    OrenAVMGfxStateKindOpacity = 3,
    OrenAVMGfxStateKindCamera = 4,
};

typedef uint8_t OrenAVMGfxPopResult;
enum {
    OrenAVMGfxPopResultNone = 0,
    OrenAVMGfxPopResultNoOp = 1,
    OrenAVMGfxPopResultRestored = 2,
};

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

static BOOL OrenAVMGfxStateKindSavesCGState(OrenAVMGfxStateKind kind) {
    return kind == OrenAVMGfxStateKindClip ||
        kind == OrenAVMGfxStateKindTransform ||
        kind == OrenAVMGfxStateKindOpacity;
}

static BOOL OrenAVMGfxPushState(CGContextRef ctx,
                                OrenAVMGfxFrameState* state,
                                OrenAVMGfxStateKind kind,
                                BOOL saveCGState) {
    if (!state || kind == 0 || (saveCGState && !ctx)) return NO;
    if (state->stateDepth >= OrenAVMGfxFrameStateStackCapacity) {
        state->stateOverflowDepth++;
        return NO;
    }
    if (saveCGState) CGContextSaveGState(ctx);
    state->stateStack[state->stateDepth++] = kind;
    return YES;
}

static OrenAVMGfxPopResult OrenAVMGfxPopState(CGContextRef ctx,
                                              OrenAVMGfxFrameState* state,
                                              OrenAVMGfxStateKind kind,
                                              BOOL restoreCGState) {
    if (!state || kind == 0 || (restoreCGState && !ctx)) return OrenAVMGfxPopResultNone;
    if (state->stateOverflowDepth > 0) {
        state->stateOverflowDepth--;
        return OrenAVMGfxPopResultNoOp;
    }
    if (state->stateDepth == 0 || state->stateStack[state->stateDepth - 1] != kind) {
        return OrenAVMGfxPopResultNone;
    }
    state->stateDepth--;
    state->stateStack[state->stateDepth] = 0;
    if (restoreCGState) CGContextRestoreGState(ctx);
    return OrenAVMGfxPopResultRestored;
}

static BOOL OrenAVMGfxPushCGState(CGContextRef ctx,
                                  OrenAVMGfxFrameState* state,
                                  OrenAVMGfxStateKind kind) {
    return OrenAVMGfxPushState(ctx, state, kind, YES);
}

static OrenAVMGfxPopResult OrenAVMGfxPopCGState(CGContextRef ctx,
                                                OrenAVMGfxFrameState* state,
                                                OrenAVMGfxStateKind kind) {
    return OrenAVMGfxPopState(ctx, state, kind, YES);
}

static BOOL OrenAVMGfxClipIsEmpty(CGContextRef ctx, BOOL alreadyEmpty) {
    if (alreadyEmpty) return YES;
    CGRect clip = CGContextGetClipBoundingBox(ctx);
    return CGRectIsEmpty(clip) || clip.size.width <= 0.0 || clip.size.height <= 0.0;
}

static BOOL OrenAVMGfxOpcodeIsClipScopedDraw(uint8_t opcode) {
    switch (opcode) {
        case 1:
        case 2:
        case 3:
        case 4:
        case 5:
        case 6:
        case 7:
        case 8:
        case 9:
        case 10:
        case 65:
        case 67:
        case 69:
        case 71:
        case 72:
        case 81:
        case 84:
        case 87:
        case 90:
        case 91:
        case 94:
            return YES;
        default:
            return NO;
    }
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

        if (OrenAVMGfxHandleFrameStateCommand(ctx, opcode, payload, payloadLen, &frameState)) {
            off += payloadLen;
            continue;
        }
        if (frameState.clipEmpty && OrenAVMGfxOpcodeIsClipScopedDraw(opcode)) {
            off += payloadLen;
            continue;
        }

        if (OrenAVMGfxDrawImmediatePrimitive(ctx, opcode, payload, payloadLen)) {
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
                                        frameState.opacity,
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
                if (OrenAVMGfxPushCGState(ctx, state, OrenAVMGfxStateKindClip)) {
                    BOOL previousClipEmpty = state->clipEmpty;
                    state->clipEmptyStack[state->clipDepth] = previousClipEmpty;
                    CGContextClipToRect(ctx, CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h));
                    state->clipEmpty = w == 0 || h == 0 || OrenAVMGfxClipIsEmpty(ctx, previousClipEmpty);
                    state->clipDepth++;
                }
            }
            return YES;
        }
        case 17: {
            if (payloadLen == 0 &&
                OrenAVMGfxPopCGState(ctx, state, OrenAVMGfxStateKindClip) == OrenAVMGfxPopResultRestored) {
                state->clipDepth--;
                state->clipEmpty = state->clipEmptyStack[state->clipDepth];
                state->clipEmptyStack[state->clipDepth] = NO;
            }
            return YES;
        }
        case 18: {
            if (payloadLen == 8) {
                int32_t dx = (int32_t)OrenAVMGfxReadU32LE(payload);
                int32_t dy = (int32_t)OrenAVMGfxReadU32LE(payload + 4);
                if (OrenAVMGfxPushCGState(ctx, state, OrenAVMGfxStateKindTransform)) {
                    CGContextTranslateCTM(ctx, (CGFloat)dx, (CGFloat)dy);
                    state->transformDepth++;
                }
            }
            return YES;
        }
        case 19: {
            if (payloadLen == 0 &&
                OrenAVMGfxPopCGState(ctx, state, OrenAVMGfxStateKindTransform) == OrenAVMGfxPopResultRestored) {
                state->transformDepth--;
            }
            return YES;
        }
        case 20: {
            if (payloadLen == 4) {
                uint32_t alphaMilli = OrenAVMGfxReadU32LE(payload);
                if (OrenAVMGfxPushCGState(ctx, state, OrenAVMGfxStateKindOpacity)) {
                    state->opacityStack[state->opacityDepth++] = state->opacity;
                    state->opacity = state->opacity * ((CGFloat)alphaMilli / 1000.0);
                    CGContextSetAlpha(ctx, state->opacity);
                }
            }
            return YES;
        }
        case 21: {
            if (payloadLen == 0) {
                OrenAVMGfxPopResult popResult = OrenAVMGfxPopCGState(ctx, state, OrenAVMGfxStateKindOpacity);
                if (popResult == OrenAVMGfxPopResultRestored) {
                    state->opacity = state->opacityStack[--state->opacityDepth];
                }
            }
            return YES;
        }
        case 22: {
            if (payloadLen == 8) {
                if (OrenAVMGfxPushState(ctx, state, OrenAVMGfxStateKindCamera, NO)) {
                    state->depthEnabledStack[state->cameraDepth] = state->depthEnabled;
                    state->nearZStack[state->cameraDepth] = state->nearZ;
                    state->farZStack[state->cameraDepth] = state->farZ;
                    state->cameraDepth++;
                    state->depthEnabled = YES;
                    state->nearZ = (int32_t)OrenAVMGfxReadU32LE(payload);
                    state->farZ = (int32_t)OrenAVMGfxReadU32LE(payload + 4);
                }
            }
            return YES;
        }
        case 23: {
            if (payloadLen == 0) {
                OrenAVMGfxPopResult popResult =
                    OrenAVMGfxPopState(ctx, state, OrenAVMGfxStateKindCamera, NO);
                if (popResult == OrenAVMGfxPopResultRestored && state->cameraDepth > 0) {
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
        OrenAVMGfxStateKind kind = state->stateStack[state->stateDepth - 1];
        state->stateStack[state->stateDepth - 1] = 0;
        state->stateDepth--;
        if (OrenAVMGfxStateKindSavesCGState(kind)) CGContextRestoreGState(ctx);
    }
    state->stateOverflowDepth = 0;
    state->clipDepth = 0;
    state->clipEmpty = NO;
    state->transformDepth = 0;
    state->opacityDepth = 0;
    state->cameraDepth = 0;
    state->depthEnabled = NO;
    state->nearZ = 0;
    state->farZ = 0;
}

#endif
