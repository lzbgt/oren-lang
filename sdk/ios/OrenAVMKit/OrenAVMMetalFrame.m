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

NSMutableArray* OrenAVMMetalEnsureRunArray(NSMutableArray** runs, NSUInteger capacity) {
    if (!runs) return nil;
    if (!*runs) *runs = [NSMutableArray arrayWithCapacity:capacity];
    return *runs;
}

uint64_t OrenAVMMetalNowNs(void) {
    return (uint64_t)llround(CACurrentMediaTime() * 1000000000.0);
}

uint64_t OrenAVMMetalTargetBudgetNs(uint32_t hzMilli) {
    uint64_t effectiveHzMilli = hzMilli == 0 ? 60000ull : (uint64_t)hzMilli;
    return 1000000000000ull / effectiveHzMilli;
}

void OrenAVMMetalFrameStateInit(OrenAVMMetalFrameState* state) {
    if (!state) return;
    memset(state, 0, sizeof(*state));
    state->opacity = 1.0f;
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
            OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
            if (state->clipDepth < 64) {
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
            OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
            if (state->clipDepth > 0) state->clip = state->clipStack[--state->clipDepth];
            return YES;
        }
        case 18: {
            if (payloadLen != 8) return NO;
            OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
            if (state->transformDepth < 64) {
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
            OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
            if (state->transformDepth > 0) {
                state->transformDepth--;
                state->tx = state->txStack[state->transformDepth];
                state->ty = state->tyStack[state->transformDepth];
            }
            return YES;
        }
        case 20: {
            if (payloadLen != 4) return NO;
            OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
            if (state->opacityDepth < 64) {
                state->opacityStack[state->opacityDepth++] = state->opacity;
                state->opacity *= (float)OrenAVMMetalReadU32LE(payload) / 1000.0f;
            }
            return YES;
        }
        case 21: {
            if (payloadLen != 0) return NO;
            OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
            if (state->opacityDepth > 0) state->opacity = state->opacityStack[--state->opacityDepth];
            return YES;
        }
        case 22: {
            if (payloadLen != 8) return NO;
            OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
            if (state->cameraDepth < 64) {
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
            OrenAVMMetalFlushVertexRun(runsRef, verticesRef, runCapacity, state->clip, YES);
            if (state->cameraDepth > 0) {
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

void OrenAVMMetalFlushVertexRun(NSMutableArray<OrenAVMMetalVertexRun*>** runsRef,
                                OrenAVMMetalVertexBuffer* verticesRef,
                                NSUInteger runCapacity,
                                OrenAVMMetalScissorState scissor,
                                BOOL continueBuilding) {
    if (!verticesRef || verticesRef->byteLength == 0) {
        if (verticesRef && verticesRef->failed) {
            NSUInteger initialCapacity = verticesRef->initialCapacity;
            OrenAVMMetalVertexBufferFree(verticesRef);
            OrenAVMMetalVertexBufferInit(verticesRef, initialCapacity);
        }
        return;
    }
    NSUInteger vertexBytes = 0;
    uint8_t* vertices = OrenAVMMetalVertexBufferTakeBytes(verticesRef, &vertexBytes);
    if (!vertices || vertexBytes == 0) return;
    NSMutableArray<OrenAVMMetalVertexRun*>* runs =
        (NSMutableArray<OrenAVMMetalVertexRun*>*)OrenAVMMetalEnsureRunArray((NSMutableArray**)runsRef, runCapacity);
    OrenAVMMetalVertexRun* run = [[OrenAVMMetalVertexRun alloc] init];
    run.vertices = vertices;
    run.vertexBytes = vertexBytes;
    run.hasScissor = scissor.enabled;
    run.scissor = scissor.rect;
    [runs addObject:run];
    (void)continueBuilding;
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
    id<MTLBuffer> buffer = [device newBufferWithBytes:bytes
                                               length:length
                                              options:MTLResourceStorageModeShared];
    if (!buffer) return NO;
    if (!transientBuffers) return NO;
    if (!*transientBuffers) *transientBuffers = [NSMutableArray array];
    if (!*transientBuffers) return NO;
    [*transientBuffers addObject:buffer];
    [encoder setVertexBuffer:buffer offset:0 atIndex:0];
    return YES;
}

#endif
