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
