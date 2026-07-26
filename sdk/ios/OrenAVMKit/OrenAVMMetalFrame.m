#import "OrenAVMMetalFrame.h"

#if TARGET_OS_IPHONE

#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <string.h>

BOOL OrenAVMMetalFrameDataIsValid(NSData* frame) {
    if (frame.length < 24) return NO;
    const uint8_t* data = (const uint8_t*)frame.bytes;
    if (memcmp(data, "OGF0", 4) != 0) return NO;
    uint8_t version = data[4];
    if (version != 0 && version != 1) return NO;
    uint16_t headerLen = version == 0 ? 24 : OrenAVMMetalReadU16LE(data + 6);
    if (headerLen < 24 || headerLen > frame.length) return NO;
    return OrenAVMMetalReadU32LE(data + 8) != 0 && OrenAVMMetalReadU32LE(data + 12) != 0;
}

NSUInteger OrenAVMMetalFrameRunCapacity(NSData* frame) {
    if (frame.length < 40) return 0;
    const uint8_t* data = (const uint8_t*)frame.bytes;
    if (memcmp(data, "OGF0", 4) != 0 || data[4] != 1) return 0;
    uint16_t headerLen = OrenAVMMetalReadU16LE(data + 6);
    if (headerLen < 40 || headerLen > frame.length) return 0;
    uint32_t opCount = OrenAVMMetalReadU32LE(data + 20);
    NSUInteger maxRecordsByBytes = (frame.length - headerLen) / 4u;
    return (NSUInteger)opCount < maxRecordsByBytes ? (NSUInteger)opCount : maxRecordsByBytes;
}

static const NSUInteger OrenAVMMetalRunArrayMaxInitialCapacity = 4096u;

static NSUInteger OrenAVMMetalRunArrayInitialCapacity(NSUInteger capacity) {
    return capacity > OrenAVMMetalRunArrayMaxInitialCapacity ? OrenAVMMetalRunArrayMaxInitialCapacity : capacity;
}

NSMutableArray* OrenAVMMetalEnsureRunArray(NSMutableArray** runs, NSUInteger capacity) {
    if (!runs) return nil;
    if (!*runs) *runs = [NSMutableArray arrayWithCapacity:OrenAVMMetalRunArrayInitialCapacity(capacity)];
    return *runs;
}

uint64_t OrenAVMMetalNowNs(void) {
    return (uint64_t)llround(CACurrentMediaTime() * 1000000000.0);
}

uint64_t OrenAVMMetalTargetBudgetNs(uint32_t hzMilli) {
    uint64_t effectiveHzMilli = hzMilli == 0 ? 60000ull : (uint64_t)hzMilli;
    return 1000000000000ull / effectiveHzMilli;
}

typedef uint8_t OrenAVMMetalStateKind;
enum {
    OrenAVMMetalStateKindClip = 1,
    OrenAVMMetalStateKindTransform = 2,
    OrenAVMMetalStateKindOpacity = 3,
    OrenAVMMetalStateKindCamera = 4,
};

typedef uint8_t OrenAVMMetalPopResult;
enum {
    OrenAVMMetalPopResultNone = 0,
    OrenAVMMetalPopResultNoOp = 1,
    OrenAVMMetalPopResultRestored = 2,
};

void OrenAVMMetalFrameStateInit(OrenAVMMetalFrameState* state) {
    if (!state) return;
    memset(state, 0, sizeof(*state));
    state->opacity = 1.0f;
}

static BOOL OrenAVMMetalPushState(OrenAVMMetalFrameState* state, OrenAVMMetalStateKind kind) {
    if (!state || kind == 0) return NO;
    if (state->stateDepth >= OrenAVMMetalFrameStateStackCapacity) {
        state->stateOverflowDepth++;
        return NO;
    }
    state->stateStack[state->stateDepth++] = kind;
    return YES;
}

static OrenAVMMetalPopResult OrenAVMMetalPopState(OrenAVMMetalFrameState* state, OrenAVMMetalStateKind kind) {
    if (!state || kind == 0) return OrenAVMMetalPopResultNone;
    if (state->stateOverflowDepth > 0) {
        state->stateOverflowDepth--;
        return OrenAVMMetalPopResultNoOp;
    }
    if (state->stateDepth == 0 || state->stateStack[state->stateDepth - 1] != kind) {
        return OrenAVMMetalPopResultNone;
    }
    state->stateDepth--;
    state->stateStack[state->stateDepth] = 0;
    return OrenAVMMetalPopResultRestored;
}

BOOL OrenAVMMetalApplyClearColorCommand(uint8_t opcode,
                                        const uint8_t* payload,
                                        uint16_t payloadLen,
                                        uint32_t logicalW,
                                        uint32_t logicalH,
                                        float opacity,
                                        MTLClearColor* clearColor) {
    if (opcode != 1 || payloadLen != 20 || !payload || !clearColor || opacity < 0.999f) return NO;
    uint32_t x = OrenAVMMetalReadU32LE(payload);
    uint32_t y = OrenAVMMetalReadU32LE(payload + 4);
    uint32_t w = OrenAVMMetalReadU32LE(payload + 8);
    uint32_t h = OrenAVMMetalReadU32LE(payload + 12);
    if (x != 0 || y != 0 || w < logicalW || h < logicalH) return NO;
    uint8_t clearRGBA[4];
    OrenAVMMetalRGBAWithOpacity(payload + 16, opacity, clearRGBA);
    if (clearRGBA[3] != 255) return NO;
    *clearColor = MTLClearColorMake((double)clearRGBA[0] / 255.0,
                                    (double)clearRGBA[1] / 255.0,
                                    (double)clearRGBA[2] / 255.0,
                                    (double)clearRGBA[3] / 255.0);
    return YES;
}

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
                                         uint32_t drawableH) {
    if (!payload || !state) return NO;
    switch (opcode) {
        case 16: {
            if (payloadLen != 16) return NO;
            if (OrenAVMMetalPushState(state, OrenAVMMetalStateKindClip)) {
                OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
                state->clipStack[state->clipDepth++] = state->clip;
                int32_t cx = (int32_t)OrenAVMMetalReadU32LE(payload);
                int32_t cy = (int32_t)OrenAVMMetalReadU32LE(payload + 4);
                MTLScissorRect next = OrenAVMMetalClipRectToScissor((int64_t)lrintf((float)cx + state->tx),
                                                                    (int64_t)lrintf((float)cy + state->ty),
                                                                    OrenAVMMetalReadU32LE(payload + 8),
                                                                    OrenAVMMetalReadU32LE(payload + 12),
                                                                    logicalW,
                                                                    logicalH,
                                                                    drawableW,
                                                                    drawableH);
                state->clip.rect = state->clip.enabled ? OrenAVMMetalIntersectScissor(state->clip.rect, next) : next;
                state->clip.enabled = YES;
            }
            return YES;
        }
        case 17: {
            if (payloadLen != 0) return NO;
            OrenAVMMetalPopResult pop = OrenAVMMetalPopState(state, OrenAVMMetalStateKindClip);
            if (pop == OrenAVMMetalPopResultRestored && state->clipDepth > 0) {
                OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
                state->clip = state->clipStack[--state->clipDepth];
            }
            return YES;
        }
        case 18: {
            if (payloadLen != 8) return NO;
            if (OrenAVMMetalPushState(state, OrenAVMMetalStateKindTransform)) {
                OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
                state->txStack[state->transformDepth] = state->tx;
                state->tyStack[state->transformDepth] = state->ty;
                state->transformDepth++;
                state->tx += (float)(int32_t)OrenAVMMetalReadU32LE(payload);
                state->ty += (float)(int32_t)OrenAVMMetalReadU32LE(payload + 4);
            }
            return YES;
        }
        case 19: {
            if (payloadLen != 0) return NO;
            OrenAVMMetalPopResult pop = OrenAVMMetalPopState(state, OrenAVMMetalStateKindTransform);
            if (pop == OrenAVMMetalPopResultRestored && state->transformDepth > 0) {
                OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
                state->transformDepth--;
                state->tx = state->txStack[state->transformDepth];
                state->ty = state->tyStack[state->transformDepth];
            }
            return YES;
        }
        case 20: {
            if (payloadLen != 4) return NO;
            if (OrenAVMMetalPushState(state, OrenAVMMetalStateKindOpacity)) {
                OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
                state->opacityStack[state->opacityDepth++] = state->opacity;
                state->opacity *= (float)OrenAVMMetalReadU32LE(payload) / 1000.0f;
            }
            return YES;
        }
        case 21: {
            if (payloadLen != 0) return NO;
            OrenAVMMetalPopResult pop = OrenAVMMetalPopState(state, OrenAVMMetalStateKindOpacity);
            if (pop == OrenAVMMetalPopResultRestored && state->opacityDepth > 0) {
                OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
                state->opacity = state->opacityStack[--state->opacityDepth];
            }
            return YES;
        }
        case 22: {
            if (payloadLen != 8) return NO;
            if (OrenAVMMetalPushState(state, OrenAVMMetalStateKindCamera)) {
                OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
                state->depthEnabledStack[state->cameraDepth] = state->depthEnabled;
                state->nearZStack[state->cameraDepth] = state->nearZ;
                state->farZStack[state->cameraDepth] = state->farZ;
                state->cameraDepth++;
                state->depthEnabled = YES;
                state->nearZ = (int32_t)OrenAVMMetalReadU32LE(payload);
                state->farZ = (int32_t)OrenAVMMetalReadU32LE(payload + 4);
            }
            return YES;
        }
        case 23: {
            if (payloadLen != 0) return NO;
            OrenAVMMetalPopResult pop = OrenAVMMetalPopState(state, OrenAVMMetalStateKindCamera);
            if (pop == OrenAVMMetalPopResultRestored && state->cameraDepth > 0) {
                OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
                state->cameraDepth--;
                state->depthEnabled = state->depthEnabledStack[state->cameraDepth];
                state->nearZ = state->nearZStack[state->cameraDepth];
                state->farZ = state->farZStack[state->cameraDepth];
            }
            return YES;
        }
        default:
            return NO;
    }
}

static BOOL OrenAVMMetalScissorIsEmpty(OrenAVMMetalScissorState clip) {
    return clip.enabled && (clip.rect.width == 0 || clip.rect.height == 0);
}

static BOOL OrenAVMMetalOpcodeIsDrawOnly(uint8_t opcode) {
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

static BOOL OrenAVMMetalHasPreparedDrawWork(NSMutableArray<OrenAVMMetalVertexRun*>* vertexRuns,
                                             OrenAVMMetalVertexBuffer* vertices,
                                             NSMutableArray<OrenAVMMetalTextRun*>** textRuns,
                                             NSMutableArray<OrenAVMMetalImageRun*>** imageRuns) {
    return vertexRuns.count > 0 ||
           (vertices && vertices->byteLength > 0) ||
           (textRuns && *textRuns && (*textRuns).count > 0) ||
           (imageRuns && *imageRuns && (*imageRuns).count > 0);
}

NSArray<OrenAVMMetalVertexRun*>* OrenAVMMetalBuildVertexRunsForFrame(NSData* frame,
                                                                     MTLClearColor* clearColor,
                                                                     NSMutableArray<OrenAVMMetalTextRun*>** textRuns,
                                                                     NSMutableArray<OrenAVMMetalImageRun*>** imageRuns,
                                                                     NSUInteger runCapacity,
                                                                     OrenAVMMetalFrameBuildContext* context) {
    NSMutableArray<OrenAVMMetalVertexRun*>* vertexRuns = nil;
    if (frame.length < 40 || !context) return @[];
    const uint8_t* data = (const uint8_t*)frame.bytes;
    if (memcmp(data, "OGF0", 4) != 0 || data[4] != 1) return @[];
    uint16_t headerLen = OrenAVMMetalReadU16LE(data + 6);
    if (headerLen < 40 || headerLen > frame.length) return @[];
    uint32_t logicalW = OrenAVMMetalReadU32LE(data + 8);
    uint32_t logicalH = OrenAVMMetalReadU32LE(data + 12);
    uint32_t opCount = OrenAVMMetalReadU32LE(data + 20);
    uint32_t drawableW = OrenAVMMetalReadU32LE(data + 28);
    uint32_t drawableH = OrenAVMMetalReadU32LE(data + 32);
    if (logicalW == 0 || logicalH == 0 || drawableW == 0 || drawableH == 0) return @[];

    OrenAVMMetalVertexBuffer vertices;
    OrenAVMMetalVertexBufferInit(&vertices, OrenAVMMetalInitialVertexBuilderCapacity(runCapacity));
    size_t off = headerLen;
    OrenAVMMetalFrameState frameState;
    OrenAVMMetalFrameStateInit(&frameState);
    NSUInteger textCachePixels = context->textCachePixels;
    OrenAVMMetalTextAtlas* textAtlas = context->textAtlas;
    for (uint32_t i = 0; i < opCount && off + 4 <= frame.length; i++) {
        uint8_t opcode = data[off];
        uint16_t payloadLen = OrenAVMMetalReadU16LE(data + off + 2);
        off += 4;
        if (off + (size_t)payloadLen > frame.length) break;
        const uint8_t* payload = data + off;
        BOOL clearHandled = NO;
        if (!frameState.clip.enabled && frameState.tx == 0.0f && frameState.ty == 0.0f) {
            clearHandled = OrenAVMMetalApplyClearColorCommand(opcode, payload, payloadLen, logicalW, logicalH, frameState.opacity, clearColor);
        }
        if (clearHandled && !OrenAVMMetalHasPreparedDrawWork(vertexRuns, &vertices, textRuns, imageRuns)) {
            off += payloadLen;
            continue;
        }
        if ((OrenAVMMetalScissorIsEmpty(frameState.clip) || frameState.opacity <= 0.0f) &&
            OrenAVMMetalOpcodeIsDrawOnly(opcode)) {
            off += payloadLen;
            continue;
        }
        BOOL primitiveHandled = OrenAVMMetalAppendPrimitiveCommand(opcode,
                                                                   payload,
                                                                   payloadLen,
                                                                   &vertices,
                                                                   frameState.tx,
                                                                   frameState.ty,
                                                                   (float)logicalW,
                                                                   (float)logicalH,
                                                                   frameState.opacity);
        if (!primitiveHandled && OrenAVMMetalHandleFrameStateCommand(opcode,
                                                                     payload,
                                                                     payloadLen,
                                                                     &vertexRuns,
                                                                     &vertices,
                                                                     runCapacity,
                                                                     &frameState,
                                                                     logicalW,
                                                                     logicalH,
                                                                     drawableW,
                                                                     drawableH)) {
        } else if (OrenAVMMetalHandleMeshCommand(context->meshes2D,
                                                 context->meshes3D,
                                                 context->materials3D,
                                                 context->models3D,
                                                 opcode,
                                                 payload,
                                                 payloadLen,
                                                 &vertices,
                                                 frameState.tx,
                                                 frameState.ty,
                                                 (float)logicalW,
                                                 (float)logicalH,
                                                 frameState.opacity,
                                                 frameState.depthEnabled,
                                                 frameState.nearZ,
                                                 frameState.farZ)) {
        } else {
            BOOL textHandled = OrenAVMMetalHandleTextCommand(context->textResources,
                                                             context->device,
                                                             context->screen,
                                                             opcode,
                                                             payload,
                                                             payloadLen,
                                                             &textAtlas,
                                                             context->textCache,
                                                             context->textCacheOrder,
                                                             context->textAttributes,
                                                             &textCachePixels,
                                                             textRuns,
                                                             runCapacity,
                                                             frameState.clip.enabled,
                                                             frameState.clip.rect,
                                                             frameState.tx,
                                                             frameState.ty,
                                                             (float)logicalW,
                                                             (float)logicalH,
                                                             frameState.opacity);
            if (!textHandled) {
                (void)OrenAVMMetalHandleImageCommand(context->images,
                                                     context->device,
                                                     opcode,
                                                     payload,
                                                     payloadLen,
                                                     imageRuns,
                                                     runCapacity,
                                                     frameState.clip.enabled,
                                                     frameState.clip.rect,
                                                     frameState.tx,
                                                     frameState.ty,
                                                     (float)logicalW,
                                                     (float)logicalH,
                                                     frameState.opacity,
                                                     context->retainedImageCountLimit,
                                                     context->retainedImagePixelLimit,
                                                     context->retainedImagePixelCount);
            }
        }
        off += payloadLen;
    }
    context->textCachePixels = textCachePixels;
    context->textAtlas = textAtlas;
    OrenAVMMetalFlushVertexRun(&vertexRuns, &vertices, runCapacity, frameState.clip, NO);
    OrenAVMMetalVertexBufferFree(&vertices);
    return vertexRuns ?: @[];
}

MTLScissorRect OrenAVMMetalClipRectToScissor(int64_t x,
                                             int64_t y,
                                             uint32_t w,
                                             uint32_t h,
                                             uint32_t logicalW,
                                             uint32_t logicalH,
                                             uint32_t drawableW,
                                             uint32_t drawableH) {
    MTLScissorRect r;
    int64_t x0 = x < 0 ? 0 : x;
    int64_t y0 = y < 0 ? 0 : y;
    int64_t x2 = x + (int64_t)w;
    int64_t y2 = y + (int64_t)h;
    if (x2 < 0) x2 = 0;
    if (y2 < 0) y2 = 0;
    r.x = logicalW == 0 ? 0 : (NSUInteger)(((uint64_t)x0 * drawableW) / logicalW);
    r.y = logicalH == 0 ? 0 : (NSUInteger)(((uint64_t)y0 * drawableH) / logicalH);
    NSUInteger x1 = logicalW == 0 ? 0 : (NSUInteger)(((uint64_t)x2 * drawableW) / logicalW);
    NSUInteger y1 = logicalH == 0 ? 0 : (NSUInteger)(((uint64_t)y2 * drawableH) / logicalH);
    if (r.x > drawableW) r.x = drawableW;
    if (r.y > drawableH) r.y = drawableH;
    if (x1 > drawableW) x1 = drawableW;
    if (y1 > drawableH) y1 = drawableH;
    r.width = x1 > r.x ? x1 - r.x : 0;
    r.height = y1 > r.y ? y1 - r.y : 0;
    return r;
}

MTLScissorRect OrenAVMMetalIntersectScissor(MTLScissorRect a, MTLScissorRect b) {
    NSUInteger x0 = a.x > b.x ? a.x : b.x;
    NSUInteger y0 = a.y > b.y ? a.y : b.y;
    NSUInteger ax1 = a.x + a.width;
    NSUInteger ay1 = a.y + a.height;
    NSUInteger bx1 = b.x + b.width;
    NSUInteger by1 = b.y + b.height;
    NSUInteger x1 = ax1 < bx1 ? ax1 : bx1;
    NSUInteger y1 = ay1 < by1 ? ay1 : by1;
    MTLScissorRect out;
    out.x = x0;
    out.y = y0;
    out.width = x1 > x0 ? x1 - x0 : 0;
    out.height = y1 > y0 ? y1 - y0 : 0;
    return out;
}

NSUInteger OrenAVMMetalInitialVertexBuilderCapacity(NSUInteger runCapacity) {
    const NSUInteger bytesPerSimpleRun = sizeof(OrenAVMMetalVertex) * 6u;
    const NSUInteger maxInitialBytes = 64u * 1024u;
    if (runCapacity == 0) return bytesPerSimpleRun;
    if (runCapacity > maxInitialBytes / bytesPerSimpleRun) return maxInitialBytes;
    return runCapacity * bytesPerSimpleRun;
}

OrenAVMMetalVertexBuffer* OrenAVMMetalEnsureVertexBuilder(OrenAVMMetalVertexBuffer* vertices, NSUInteger runCapacity) {
    if (vertices && vertices->initialCapacity == 0) {
        OrenAVMMetalVertexBufferInit(vertices, OrenAVMMetalInitialVertexBuilderCapacity(runCapacity));
    }
    return vertices;
}

static void OrenAVMMetalResetFailedVertexBuilder(OrenAVMMetalVertexBuffer* vertices, BOOL continueBuilding) {
    if (!vertices || !vertices->failed) return;
    NSUInteger initialCapacity = vertices->initialCapacity;
    OrenAVMMetalVertexBufferFree(vertices);
    if (continueBuilding) OrenAVMMetalVertexBufferInit(vertices, initialCapacity);
}

void OrenAVMMetalFlushVertexRun(NSMutableArray<OrenAVMMetalVertexRun*>** runsRef,
                                OrenAVMMetalVertexBuffer* verticesRef,
                                NSUInteger runCapacity,
                                OrenAVMMetalScissorState scissor,
                                BOOL continueBuilding) {
    if (verticesRef && verticesRef->failed) {
        OrenAVMMetalResetFailedVertexBuilder(verticesRef, continueBuilding);
        return;
    }
    if (!verticesRef || verticesRef->byteLength == 0) {
        return;
    }
    NSUInteger vertexBytes = 0;
    uint8_t* vertices = OrenAVMMetalVertexBufferTakeBytes(verticesRef, &vertexBytes);
    if (!vertices || vertexBytes == 0) return;
    NSMutableArray<OrenAVMMetalVertexRun*>* runs =
        (NSMutableArray<OrenAVMMetalVertexRun*>*)OrenAVMMetalEnsureRunArray((NSMutableArray**)runsRef, runCapacity);
    if (!runs) {
        free(vertices);
        return;
    }
    OrenAVMMetalVertexRun* run = [[OrenAVMMetalVertexRun alloc] init];
    if (!run) {
        free(vertices);
        return;
    }
    run.vertices = vertices;
    run.vertexBytes = vertexBytes;
    run.vertexCapacity = vertexBytes;
    run.hasScissor = scissor.enabled;
    run.scissor = scissor.rect;
    [runs addObject:run];
}

static BOOL OrenAVMMetalVertexRunScissorEqual(OrenAVMMetalVertexRun* a, OrenAVMMetalVertexRun* b) {
    if (!a || !b || a.hasScissor != b.hasScissor) return NO;
    if (!a.hasScissor) return YES;
    return a.scissor.x == b.scissor.x &&
        a.scissor.y == b.scissor.y &&
        a.scissor.width == b.scissor.width &&
        a.scissor.height == b.scissor.height;
}

static BOOL OrenAVMMetalVertexRunAppendBytes(OrenAVMMetalVertexRun* pending, const uint8_t* bytes, NSUInteger length) {
    if (!pending || !bytes || length == 0) return NO;
    if (pending.vertexBytes > NSUIntegerMax - length) return NO;
    NSUInteger needed = pending.vertexBytes + length;
    if (needed > pending.vertexCapacity) {
        NSUInteger newCapacity = pending.vertexCapacity > 0 ? pending.vertexCapacity : sizeof(OrenAVMMetalVertex) * 6u;
        while (newCapacity < needed) {
            if (newCapacity > NSUIntegerMax / 2u) {
                newCapacity = needed;
                break;
            }
            newCapacity *= 2u;
        }
        uint8_t* merged = (uint8_t*)realloc(pending.vertices, newCapacity);
        if (!merged) return NO;
        pending.vertices = merged;
        pending.vertexCapacity = newCapacity;
    }
    memcpy(pending.vertices + pending.vertexBytes, bytes, length);
    pending.vertexBytes = needed;
    return YES;
}

static BOOL OrenAVMMetalScissorRectEqual(MTLScissorRect a, MTLScissorRect b) {
    return a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height;
}

static void OrenAVMMetalApplyScissorIfNeeded(id<MTLRenderCommandEncoder> encoder,
                                             MTLScissorRect scissor,
                                             BOOL* hasLastScissor,
                                             MTLScissorRect* lastScissor) {
    if (!encoder || !hasLastScissor || !lastScissor) return;
    if (*hasLastScissor && OrenAVMMetalScissorRectEqual(*lastScissor, scissor)) return;
    [encoder setScissorRect:scissor];
    *lastScissor = scissor;
    *hasLastScissor = YES;
}

static void OrenAVMMetalApplyFragmentTextureIfNeeded(id<MTLRenderCommandEncoder> encoder,
                                                     id<MTLTexture> texture,
                                                     id<MTLTexture>* lastTexture) {
    if (!encoder || !texture || !lastTexture || *lastTexture == texture) return;
    [encoder setFragmentTexture:texture atIndex:0];
    *lastTexture = texture;
}

static void OrenAVMMetalApplyFragmentOpacityIfNeeded(id<MTLRenderCommandEncoder> encoder,
                                                     float opacity,
                                                     BOOL* hasLastOpacity,
                                                     float* lastOpacity) {
    if (!encoder || !hasLastOpacity || !lastOpacity) return;
    if (*hasLastOpacity && *lastOpacity == opacity) return;
    [encoder setFragmentBytes:&opacity length:sizeof(opacity) atIndex:0];
    *lastOpacity = opacity;
    *hasLastOpacity = YES;
}

static void OrenAVMMetalApplyPipelineIfNeeded(id<MTLRenderCommandEncoder> encoder,
                                              id<MTLRenderPipelineState> pipeline,
                                              id<MTLRenderPipelineState>* currentPipeline) {
    if (!encoder || !pipeline || !currentPipeline || *currentPipeline == pipeline) return;
    [encoder setRenderPipelineState:pipeline];
    *currentPipeline = pipeline;
}

NSArray<OrenAVMMetalVertexRun*>* OrenAVMMetalCoalesceVertexRuns(NSArray<OrenAVMMetalVertexRun*>* runs) {
    if (runs.count < 2) return runs ?: @[];
    NSMutableArray<OrenAVMMetalVertexRun*>* out = [NSMutableArray arrayWithCapacity:runs.count];
    if (!out) return runs;
    OrenAVMMetalVertexRun* pending = nil;
    for (OrenAVMMetalVertexRun* run in runs) {
        if (!run.vertices || run.vertexBytes == 0) continue;
        if (pending &&
            OrenAVMMetalVertexRunScissorEqual(pending, run) &&
            OrenAVMMetalVertexRunAppendBytes(pending, run.vertices, run.vertexBytes)) {
            continue;
        }
        pending = run;
        [out addObject:pending];
    }
    return out;
}

BOOL OrenAVMMetalBindVertexPayload(id<MTLRenderCommandEncoder> encoder,
                                   id<MTLDevice> device,
                                   NSMutableArray<id<MTLBuffer>>** transientBuffers,
                                   const void* bytes,
                                   NSUInteger length) {
    if (!encoder || !bytes || length == 0) return NO;
    if (length <= OrenAVMMetalInlineVertexBytesLimit) {
        [encoder setVertexBytes:bytes length:length atIndex:0];
        return YES;
    }
    if (!transientBuffers) return NO;
    if (!*transientBuffers) *transientBuffers = [NSMutableArray array];
    if (!*transientBuffers) return NO;
    id<MTLBuffer> buffer = [device newBufferWithBytes:bytes
                                               length:length
                                              options:MTLResourceStorageModeShared];
    if (!buffer) return NO;
    [*transientBuffers addObject:buffer];
    [encoder setVertexBuffer:buffer offset:0 atIndex:0];
    return YES;
}

void OrenAVMMetalEncodePreparedRuns(id<MTLRenderCommandEncoder> encoder,
                                    id<MTLDevice> device,
                                    id<MTLRenderPipelineState> geometryPipeline,
                                    id<MTLRenderPipelineState> textPipeline,
                                    id<MTLTexture> drawableTexture,
                                    NSArray<OrenAVMMetalVertexRun*>* vertexRuns,
                                    NSArray<OrenAVMMetalImageRun*>* imageRuns,
                                    NSArray<OrenAVMMetalTextRun*>* textRuns,
                                    NSMutableArray<id<MTLBuffer>>** transientBuffers) {
    if (!encoder || !device || !drawableTexture) return;
    MTLScissorRect fullScissor = (MTLScissorRect){0, 0, (NSUInteger)drawableTexture.width, (NSUInteger)drawableTexture.height};
    BOOL hasLastScissor = NO;
    MTLScissorRect lastScissor = {0, 0, 0, 0};
    id<MTLRenderPipelineState> currentPipeline = nil;
    if (geometryPipeline && vertexRuns.count > 0) {
        for (OrenAVMMetalVertexRun* run in vertexRuns) {
            if (!run.vertices || run.vertexBytes == 0) continue;
            MTLScissorRect scissor = run.hasScissor ? run.scissor : fullScissor;
            if (scissor.width == 0 || scissor.height == 0) continue;
            OrenAVMMetalApplyScissorIfNeeded(encoder, scissor, &hasLastScissor, &lastScissor);
            if (!OrenAVMMetalBindVertexPayload(encoder, device, transientBuffers, run.vertices, run.vertexBytes)) continue;
            OrenAVMMetalApplyPipelineIfNeeded(encoder, geometryPipeline, &currentPipeline);
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                         vertexStart:0
                         vertexCount:run.vertexBytes / sizeof(OrenAVMMetalVertex)];
        }
    }
    BOOL hasTextureRuns = imageRuns.count > 0 || textRuns.count > 0;
    if (textPipeline && hasTextureRuns) {
        id<MTLTexture> lastFragmentTexture = nil;
        BOOL hasLastFragmentOpacity = NO;
        float lastFragmentOpacity = 0.0f;
        for (OrenAVMMetalImageRun* run in imageRuns) {
            NSUInteger vertexBytes = OrenAVMMetalImageRunVertexBytesLength(run);
            if (!run.texture || vertexBytes == 0) continue;
            MTLScissorRect scissor = run.hasScissor ? run.scissor : fullScissor;
            if (scissor.width == 0 || scissor.height == 0) continue;
            OrenAVMMetalApplyScissorIfNeeded(encoder, scissor, &hasLastScissor, &lastScissor);
            if (!OrenAVMMetalBindVertexPayload(encoder, device, transientBuffers, OrenAVMMetalImageRunVertexBytes(run), vertexBytes)) continue;
            OrenAVMMetalApplyPipelineIfNeeded(encoder, textPipeline, &currentPipeline);
            OrenAVMMetalApplyFragmentTextureIfNeeded(encoder, run.texture, &lastFragmentTexture);
            OrenAVMMetalApplyFragmentOpacityIfNeeded(encoder, run.opacity, &hasLastFragmentOpacity, &lastFragmentOpacity);
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                         vertexStart:0
                         vertexCount:OrenAVMMetalImageRunVertexCount(run)];
        }
        for (OrenAVMMetalTextRun* run in textRuns) {
            NSUInteger vertexBytes = OrenAVMMetalTextRunVertexBytesLength(run);
            if (!run.texture || vertexBytes == 0) continue;
            MTLScissorRect scissor = run.hasScissor ? run.scissor : fullScissor;
            if (scissor.width == 0 || scissor.height == 0) continue;
            OrenAVMMetalApplyScissorIfNeeded(encoder, scissor, &hasLastScissor, &lastScissor);
            if (!OrenAVMMetalBindVertexPayload(encoder, device, transientBuffers, OrenAVMMetalTextRunVertexBytes(run), vertexBytes)) continue;
            OrenAVMMetalApplyPipelineIfNeeded(encoder, textPipeline, &currentPipeline);
            OrenAVMMetalApplyFragmentTextureIfNeeded(encoder, run.texture, &lastFragmentTexture);
            OrenAVMMetalApplyFragmentOpacityIfNeeded(encoder, run.opacity, &hasLastFragmentOpacity, &lastFragmentOpacity);
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                         vertexStart:0
                         vertexCount:OrenAVMMetalTextRunVertexCount(run)];
        }
    }
}

#endif
