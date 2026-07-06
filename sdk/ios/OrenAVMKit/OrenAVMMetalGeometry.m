#import "OrenAVMMetalGeometry.h"

#if TARGET_OS_IPHONE

#include <math.h>
#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(OrenAVMMetalVertex) == 24, "OrenAVMMetalVertex must match shader packed_float2+packed_float4");

void OrenAVMMetalVertexBufferInit(OrenAVMMetalVertexBuffer* buffer, NSUInteger initialCapacity) {
    if (!buffer) return;
    buffer->bytes = NULL;
    buffer->byteLength = 0;
    buffer->byteCapacity = 0;
    buffer->initialCapacity = initialCapacity;
    buffer->failed = NO;
}

void OrenAVMMetalVertexBufferFree(OrenAVMMetalVertexBuffer* buffer) {
    if (!buffer) return;
    free(buffer->bytes);
    buffer->bytes = NULL;
    buffer->byteLength = 0;
    buffer->byteCapacity = 0;
}

uint8_t* OrenAVMMetalVertexBufferTakeBytes(OrenAVMMetalVertexBuffer* buffer, NSUInteger* byteLengthOut) {
    if (!buffer || buffer->failed || buffer->byteLength == 0) {
        if (byteLengthOut) *byteLengthOut = 0;
        return NULL;
    }
    uint8_t* bytes = buffer->bytes;
    if (byteLengthOut) *byteLengthOut = buffer->byteLength;
    buffer->bytes = NULL;
    buffer->byteLength = 0;
    buffer->byteCapacity = 0;
    return bytes;
}

static BOOL OrenAVMMetalVertexBufferAppend(OrenAVMMetalVertexBuffer* buffer, const OrenAVMMetalVertex* vertices, NSUInteger byteLength) {
    if (!buffer || !vertices || byteLength == 0 || buffer->failed) return NO;
    if (byteLength > NSUIntegerMax - buffer->byteLength) {
        buffer->failed = YES;
        return NO;
    }
    NSUInteger required = buffer->byteLength + byteLength;
    if (required > buffer->byteCapacity) {
        NSUInteger nextCapacity = buffer->byteCapacity;
        if (nextCapacity == 0) nextCapacity = buffer->initialCapacity > 0 ? buffer->initialCapacity : sizeof(OrenAVMMetalVertex) * 6u;
        while (nextCapacity < required) {
            if (nextCapacity > NSUIntegerMax / 2u) {
                nextCapacity = required;
                break;
            }
            nextCapacity *= 2u;
        }
        uint8_t* next = (uint8_t*)realloc(buffer->bytes, nextCapacity);
        if (!next) {
            buffer->failed = YES;
            return NO;
        }
        buffer->bytes = next;
        buffer->byteCapacity = nextCapacity;
    }
    memcpy(buffer->bytes + buffer->byteLength, vertices, byteLength);
    buffer->byteLength = required;
    return YES;
}

static float OrenAVMMetalClipX(float x, float logicalWidth) {
    return logicalWidth <= 0.0f ? 0.0f : (x / logicalWidth) * 2.0f - 1.0f;
}

static float OrenAVMMetalClipY(float y, float logicalHeight) {
    return logicalHeight <= 0.0f ? 0.0f : 1.0f - (y / logicalHeight) * 2.0f;
}

static OrenAVMMetalVertex OrenAVMMetalMakeVertex(float x,
                                                 float y,
                                                 float logicalWidth,
                                                 float logicalHeight,
                                                 const uint8_t* rgba) {
    OrenAVMMetalVertex v;
    v.x = OrenAVMMetalClipX(x, logicalWidth);
    v.y = OrenAVMMetalClipY(y, logicalHeight);
    v.r = (float)rgba[0] / 255.0f;
    v.g = (float)rgba[1] / 255.0f;
    v.b = (float)rgba[2] / 255.0f;
    v.a = (float)rgba[3] / 255.0f;
    return v;
}

static uint32_t OrenAVMMetalGeometryReadU32LE(const uint8_t* p) {
    return ((uint32_t)p[0]) | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

void OrenAVMMetalRGBAWithOpacity(const uint8_t* rgba, float opacity, uint8_t out[4]) {
    out[0] = rgba[0];
    out[1] = rgba[1];
    out[2] = rgba[2];
    float alpha = ((float)rgba[3] * opacity);
    if (alpha < 0.0f) alpha = 0.0f;
    if (alpha > 255.0f) alpha = 255.0f;
    out[3] = (uint8_t)lrintf(alpha);
}

void OrenAVMMetalRGBAValueWithOpacity(uint32_t rgbaValue, float opacity, uint8_t out[4]) {
    out[0] = (uint8_t)(rgbaValue & 255u);
    out[1] = (uint8_t)((rgbaValue >> 8) & 255u);
    out[2] = (uint8_t)((rgbaValue >> 16) & 255u);
    float alpha = (float)((rgbaValue >> 24) & 255u) * opacity;
    if (alpha < 0.0f) alpha = 0.0f;
    if (alpha > 255.0f) alpha = 255.0f;
    out[3] = (uint8_t)lrintf(alpha);
}

void OrenAVMMetalRGBAValueBytes(uint32_t rgbaValue, uint8_t out[4]) {
    out[0] = (uint8_t)(rgbaValue & 255u);
    out[1] = (uint8_t)((rgbaValue >> 8) & 255u);
    out[2] = (uint8_t)((rgbaValue >> 16) & 255u);
    out[3] = (uint8_t)((rgbaValue >> 24) & 255u);
}

void OrenAVMMetalAppendRect(OrenAVMMetalVertexBuffer* vertices,
                            float x,
                            float y,
                            float w,
                            float h,
                            float logicalWidth,
                            float logicalHeight,
                            const uint8_t* rgba) {
    OrenAVMMetalVertex out[6];
    out[0] = OrenAVMMetalMakeVertex(x, y, logicalWidth, logicalHeight, rgba);
    out[1] = OrenAVMMetalMakeVertex(x + w, y, logicalWidth, logicalHeight, rgba);
    out[2] = OrenAVMMetalMakeVertex(x, y + h, logicalWidth, logicalHeight, rgba);
    out[3] = OrenAVMMetalMakeVertex(x + w, y, logicalWidth, logicalHeight, rgba);
    out[4] = OrenAVMMetalMakeVertex(x + w, y + h, logicalWidth, logicalHeight, rgba);
    out[5] = OrenAVMMetalMakeVertex(x, y + h, logicalWidth, logicalHeight, rgba);
    (void)OrenAVMMetalVertexBufferAppend(vertices, out, sizeof(out));
}

void OrenAVMMetalAppendLine(OrenAVMMetalVertexBuffer* vertices,
                            float x1,
                            float y1,
                            float x2,
                            float y2,
                            float width,
                            float logicalWidth,
                            float logicalHeight,
                            const uint8_t* rgba) {
    float dx = x2 - x1;
    float dy = y2 - y1;
    float len = sqrtf(dx * dx + dy * dy);
    if (len <= 0.0001f) {
        float side = width <= 0.0f ? 1.0f : width;
        OrenAVMMetalAppendRect(vertices, x1, y1, side, side, logicalWidth, logicalHeight, rgba);
        return;
    }
    float halfWidth = (width <= 0.0f ? 1.0f : width) * 0.5f;
    float nx = -dy / len * halfWidth;
    float ny = dx / len * halfWidth;
    OrenAVMMetalVertex out[6];
    out[0] = OrenAVMMetalMakeVertex(x1 + nx, y1 + ny, logicalWidth, logicalHeight, rgba);
    out[1] = OrenAVMMetalMakeVertex(x2 + nx, y2 + ny, logicalWidth, logicalHeight, rgba);
    out[2] = OrenAVMMetalMakeVertex(x1 - nx, y1 - ny, logicalWidth, logicalHeight, rgba);
    out[3] = OrenAVMMetalMakeVertex(x2 + nx, y2 + ny, logicalWidth, logicalHeight, rgba);
    out[4] = OrenAVMMetalMakeVertex(x2 - nx, y2 - ny, logicalWidth, logicalHeight, rgba);
    out[5] = OrenAVMMetalMakeVertex(x1 - nx, y1 - ny, logicalWidth, logicalHeight, rgba);
    (void)OrenAVMMetalVertexBufferAppend(vertices, out, sizeof(out));
}

void OrenAVMMetalAppendStrokeRect(OrenAVMMetalVertexBuffer* vertices,
                                  float x,
                                  float y,
                                  float w,
                                  float h,
                                  float width,
                                  float logicalWidth,
                                  float logicalHeight,
                                  const uint8_t* rgba) {
    float lw = width <= 0.0f ? 1.0f : width;
    OrenAVMMetalAppendRect(vertices, x, y, w, lw, logicalWidth, logicalHeight, rgba);
    OrenAVMMetalAppendRect(vertices, x, y + h - lw, w, lw, logicalWidth, logicalHeight, rgba);
    OrenAVMMetalAppendRect(vertices, x, y, lw, h, logicalWidth, logicalHeight, rgba);
    OrenAVMMetalAppendRect(vertices, x + w - lw, y, lw, h, logicalWidth, logicalHeight, rgba);
}

void OrenAVMMetalAppendTriangle(OrenAVMMetalVertexBuffer* vertices,
                                float x1,
                                float y1,
                                float x2,
                                float y2,
                                float x3,
                                float y3,
                                float logicalWidth,
                                float logicalHeight,
                                const uint8_t* rgba) {
    OrenAVMMetalVertex out[3];
    out[0] = OrenAVMMetalMakeVertex(x1, y1, logicalWidth, logicalHeight, rgba);
    out[1] = OrenAVMMetalMakeVertex(x2, y2, logicalWidth, logicalHeight, rgba);
    out[2] = OrenAVMMetalMakeVertex(x3, y3, logicalWidth, logicalHeight, rgba);
    (void)OrenAVMMetalVertexBufferAppend(vertices, out, sizeof(out));
}

void OrenAVMMetalAppendCircle(OrenAVMMetalVertexBuffer* vertices,
                              float cx,
                              float cy,
                              float radius,
                              BOOL filled,
                              float logicalWidth,
                              float logicalHeight,
                              const uint8_t* rgba) {
    if (radius <= 0.0f) return;
    const int segments = 32;
    const float pi = acosf(-1.0f);
    if (filled) {
        for (int i = 0; i < segments; i++) {
            float a0 = ((float)i / (float)segments) * 2.0f * pi;
            float a1 = ((float)(i + 1) / (float)segments) * 2.0f * pi;
            OrenAVMMetalVertex out[3];
            out[0] = OrenAVMMetalMakeVertex(cx, cy, logicalWidth, logicalHeight, rgba);
            out[1] = OrenAVMMetalMakeVertex(cx + cosf(a0) * radius,
                                            cy + sinf(a0) * radius,
                                            logicalWidth,
                                            logicalHeight,
                                            rgba);
            out[2] = OrenAVMMetalMakeVertex(cx + cosf(a1) * radius,
                                            cy + sinf(a1) * radius,
                                            logicalWidth,
                                            logicalHeight,
                                            rgba);
            (void)OrenAVMMetalVertexBufferAppend(vertices, out, sizeof(out));
        }
        return;
    }
    for (int i = 0; i < segments; i++) {
        float a0 = ((float)i / (float)segments) * 2.0f * pi;
        float a1 = ((float)(i + 1) / (float)segments) * 2.0f * pi;
        OrenAVMMetalAppendLine(vertices,
                               cx + cosf(a0) * radius,
                               cy + sinf(a0) * radius,
                               cx + cosf(a1) * radius,
                               cy + sinf(a1) * radius,
                               1.0f,
                               logicalWidth,
                               logicalHeight,
                               rgba);
    }
}

void OrenAVMMetalAppendEllipse(OrenAVMMetalVertexBuffer* vertices,
                               float x,
                               float y,
                               float w,
                               float h,
                               float width,
                               BOOL filled,
                               float logicalWidth,
                               float logicalHeight,
                               const uint8_t* rgba) {
    if (w <= 0.0f || h <= 0.0f) return;
    const int segments = 32;
    const float pi = acosf(-1.0f);
    float cx = x + (w * 0.5f);
    float cy = y + (h * 0.5f);
    float rx = w * 0.5f;
    float ry = h * 0.5f;
    if (filled) {
        for (int i = 0; i < segments; i++) {
            float a0 = ((float)i / (float)segments) * 2.0f * pi;
            float a1 = ((float)(i + 1) / (float)segments) * 2.0f * pi;
            OrenAVMMetalVertex out[3];
            out[0] = OrenAVMMetalMakeVertex(cx, cy, logicalWidth, logicalHeight, rgba);
            out[1] = OrenAVMMetalMakeVertex(cx + cosf(a0) * rx,
                                            cy + sinf(a0) * ry,
                                            logicalWidth,
                                            logicalHeight,
                                            rgba);
            out[2] = OrenAVMMetalMakeVertex(cx + cosf(a1) * rx,
                                            cy + sinf(a1) * ry,
                                            logicalWidth,
                                            logicalHeight,
                                            rgba);
            (void)OrenAVMMetalVertexBufferAppend(vertices, out, sizeof(out));
        }
        return;
    }
    float lw = width <= 0.0f ? 1.0f : width;
    for (int i = 0; i < segments; i++) {
        float a0 = ((float)i / (float)segments) * 2.0f * pi;
        float a1 = ((float)(i + 1) / (float)segments) * 2.0f * pi;
        OrenAVMMetalAppendLine(vertices,
                               cx + cosf(a0) * rx,
                               cy + sinf(a0) * ry,
                               cx + cosf(a1) * rx,
                               cy + sinf(a1) * ry,
                               lw,
                               logicalWidth,
                               logicalHeight,
                               rgba);
    }
}

static void OrenAVMMetalAppendSector(OrenAVMMetalVertexBuffer* vertices,
                                     float cx,
                                     float cy,
                                     float radius,
                                     float a0,
                                     float a1,
                                     float logicalWidth,
                                     float logicalHeight,
                                     const uint8_t* rgba) {
    if (radius <= 0.0f) return;
    const int segments = 8;
    for (int i = 0; i < segments; i++) {
        float t0 = a0 + ((a1 - a0) * ((float)i / (float)segments));
        float t1 = a0 + ((a1 - a0) * ((float)(i + 1) / (float)segments));
        OrenAVMMetalVertex out[3];
        out[0] = OrenAVMMetalMakeVertex(cx, cy, logicalWidth, logicalHeight, rgba);
        out[1] = OrenAVMMetalMakeVertex(cx + cosf(t0) * radius,
                                        cy + sinf(t0) * radius,
                                        logicalWidth,
                                        logicalHeight,
                                        rgba);
        out[2] = OrenAVMMetalMakeVertex(cx + cosf(t1) * radius,
                                        cy + sinf(t1) * radius,
                                        logicalWidth,
                                        logicalHeight,
                                        rgba);
        (void)OrenAVMMetalVertexBufferAppend(vertices, out, sizeof(out));
    }
}

static void OrenAVMMetalAppendArcLines(OrenAVMMetalVertexBuffer* vertices,
                                       float cx,
                                       float cy,
                                       float radius,
                                       float a0,
                                       float a1,
                                       float width,
                                       float logicalWidth,
                                       float logicalHeight,
                                       const uint8_t* rgba) {
    if (radius <= 0.0f) return;
    const int segments = 8;
    float lastX = cx + cosf(a0) * radius;
    float lastY = cy + sinf(a0) * radius;
    for (int i = 1; i <= segments; i++) {
        float t = a0 + ((a1 - a0) * ((float)i / (float)segments));
        float x = cx + cosf(t) * radius;
        float y = cy + sinf(t) * radius;
        OrenAVMMetalAppendLine(vertices, lastX, lastY, x, y, width, logicalWidth, logicalHeight, rgba);
        lastX = x;
        lastY = y;
    }
}

void OrenAVMMetalAppendRoundRect(OrenAVMMetalVertexBuffer* vertices,
                                 float x,
                                 float y,
                                 float w,
                                 float h,
                                 float radius,
                                 float width,
                                 BOOL filled,
                                 float logicalWidth,
                                 float logicalHeight,
                                 const uint8_t* rgba) {
    if (w <= 0.0f || h <= 0.0f) return;
    float r = radius;
    if (r < 0.0f) r = 0.0f;
    if (r > w * 0.5f) r = w * 0.5f;
    if (r > h * 0.5f) r = h * 0.5f;
    if (r <= 0.0f) {
        if (filled) {
            OrenAVMMetalAppendRect(vertices, x, y, w, h, logicalWidth, logicalHeight, rgba);
        } else {
            OrenAVMMetalAppendStrokeRect(vertices, x, y, w, h, width, logicalWidth, logicalHeight, rgba);
        }
        return;
    }
    const float pi = acosf(-1.0f);
    if (filled) {
        if (w - (2.0f * r) > 0.0f) {
            OrenAVMMetalAppendRect(vertices, x + r, y, w - (2.0f * r), h, logicalWidth, logicalHeight, rgba);
        }
        if (h - (2.0f * r) > 0.0f) {
            OrenAVMMetalAppendRect(vertices, x, y + r, r, h - (2.0f * r), logicalWidth, logicalHeight, rgba);
            OrenAVMMetalAppendRect(vertices, x + w - r, y + r, r, h - (2.0f * r), logicalWidth, logicalHeight, rgba);
        }
        OrenAVMMetalAppendSector(vertices, x + r, y + r, r, pi, pi * 1.5f, logicalWidth, logicalHeight, rgba);
        OrenAVMMetalAppendSector(vertices, x + w - r, y + r, r, pi * 1.5f, pi * 2.0f, logicalWidth, logicalHeight, rgba);
        OrenAVMMetalAppendSector(vertices, x + w - r, y + h - r, r, 0.0f, pi * 0.5f, logicalWidth, logicalHeight, rgba);
        OrenAVMMetalAppendSector(vertices, x + r, y + h - r, r, pi * 0.5f, pi, logicalWidth, logicalHeight, rgba);
        return;
    }
    float lw = width <= 0.0f ? 1.0f : width;
    OrenAVMMetalAppendLine(vertices, x + r, y, x + w - r, y, lw, logicalWidth, logicalHeight, rgba);
    OrenAVMMetalAppendLine(vertices, x + w, y + r, x + w, y + h - r, lw, logicalWidth, logicalHeight, rgba);
    OrenAVMMetalAppendLine(vertices, x + w - r, y + h, x + r, y + h, lw, logicalWidth, logicalHeight, rgba);
    OrenAVMMetalAppendLine(vertices, x, y + h - r, x, y + r, lw, logicalWidth, logicalHeight, rgba);
    OrenAVMMetalAppendArcLines(vertices, x + r, y + r, r, pi, pi * 1.5f, lw, logicalWidth, logicalHeight, rgba);
    OrenAVMMetalAppendArcLines(vertices, x + w - r, y + r, r, pi * 1.5f, pi * 2.0f, lw, logicalWidth, logicalHeight, rgba);
    OrenAVMMetalAppendArcLines(vertices, x + w - r, y + h - r, r, 0.0f, pi * 0.5f, lw, logicalWidth, logicalHeight, rgba);
    OrenAVMMetalAppendArcLines(vertices, x + r, y + h - r, r, pi * 0.5f, pi, lw, logicalWidth, logicalHeight, rgba);
}

BOOL OrenAVMMetalAppendPrimitiveCommand(uint8_t opcode,
                                        const uint8_t* payload,
                                        uint16_t payloadLen,
                                        OrenAVMMetalVertexBuffer* vertices,
                                        float tx,
                                        float ty,
                                        float logicalWidth,
                                        float logicalHeight,
                                        float opacity) {
    if (!payload || !vertices) return NO;
    uint8_t rgba[4];
    switch (opcode) {
        case 1: {
            if (payloadLen == 20) {
                uint32_t x = OrenAVMMetalGeometryReadU32LE(payload);
                uint32_t y = OrenAVMMetalGeometryReadU32LE(payload + 4);
                uint32_t w = OrenAVMMetalGeometryReadU32LE(payload + 8);
                uint32_t h = OrenAVMMetalGeometryReadU32LE(payload + 12);
                OrenAVMMetalRGBAWithOpacity(payload + 16, opacity, rgba);
                OrenAVMMetalAppendRect(vertices, (float)x + tx, (float)y + ty, (float)w, (float)h, logicalWidth, logicalHeight, rgba);
            }
            return YES;
        }
        case 3: {
            if (payloadLen == 24) {
                uint32_t x1 = OrenAVMMetalGeometryReadU32LE(payload);
                uint32_t y1 = OrenAVMMetalGeometryReadU32LE(payload + 4);
                uint32_t x2 = OrenAVMMetalGeometryReadU32LE(payload + 8);
                uint32_t y2 = OrenAVMMetalGeometryReadU32LE(payload + 12);
                uint32_t width = OrenAVMMetalGeometryReadU32LE(payload + 16);
                OrenAVMMetalRGBAWithOpacity(payload + 20, opacity, rgba);
                OrenAVMMetalAppendLine(vertices,
                                       (float)x1 + tx,
                                       (float)y1 + ty,
                                       (float)x2 + tx,
                                       (float)y2 + ty,
                                       (float)(width == 0 ? 1u : width),
                                       logicalWidth,
                                       logicalHeight,
                                       rgba);
            }
            return YES;
        }
        case 4: {
            if (payloadLen == 20) {
                uint32_t cx = OrenAVMMetalGeometryReadU32LE(payload);
                uint32_t cy = OrenAVMMetalGeometryReadU32LE(payload + 4);
                uint32_t radius = OrenAVMMetalGeometryReadU32LE(payload + 8);
                uint32_t flags = OrenAVMMetalGeometryReadU32LE(payload + 12);
                OrenAVMMetalRGBAWithOpacity(payload + 16, opacity, rgba);
                OrenAVMMetalAppendCircle(vertices,
                                         (float)cx + tx,
                                         (float)cy + ty,
                                         (float)radius,
                                         (flags & 1u) != 0,
                                         logicalWidth,
                                         logicalHeight,
                                         rgba);
            }
            return YES;
        }
        case 5: {
            if (payloadLen == 28) {
                uint32_t x1 = OrenAVMMetalGeometryReadU32LE(payload);
                uint32_t y1 = OrenAVMMetalGeometryReadU32LE(payload + 4);
                uint32_t x2 = OrenAVMMetalGeometryReadU32LE(payload + 8);
                uint32_t y2 = OrenAVMMetalGeometryReadU32LE(payload + 12);
                uint32_t x3 = OrenAVMMetalGeometryReadU32LE(payload + 16);
                uint32_t y3 = OrenAVMMetalGeometryReadU32LE(payload + 20);
                OrenAVMMetalRGBAWithOpacity(payload + 24, opacity, rgba);
                OrenAVMMetalAppendTriangle(vertices,
                                           (float)x1 + tx,
                                           (float)y1 + ty,
                                           (float)x2 + tx,
                                           (float)y2 + ty,
                                           (float)x3 + tx,
                                           (float)y3 + ty,
                                           logicalWidth,
                                           logicalHeight,
                                           rgba);
            }
            return YES;
        }
        case 6: {
            if (payloadLen == 24) {
                uint32_t x = OrenAVMMetalGeometryReadU32LE(payload);
                uint32_t y = OrenAVMMetalGeometryReadU32LE(payload + 4);
                uint32_t w = OrenAVMMetalGeometryReadU32LE(payload + 8);
                uint32_t h = OrenAVMMetalGeometryReadU32LE(payload + 12);
                uint32_t width = OrenAVMMetalGeometryReadU32LE(payload + 16);
                OrenAVMMetalRGBAWithOpacity(payload + 20, opacity, rgba);
                OrenAVMMetalAppendStrokeRect(vertices,
                                             (float)x + tx,
                                             (float)y + ty,
                                             (float)w,
                                             (float)h,
                                             (float)(width == 0 ? 1u : width),
                                             logicalWidth,
                                             logicalHeight,
                                             rgba);
            }
            return YES;
        }
        case 7: {
            if (payloadLen == 28) {
                uint32_t x = OrenAVMMetalGeometryReadU32LE(payload);
                uint32_t y = OrenAVMMetalGeometryReadU32LE(payload + 4);
                uint32_t w = OrenAVMMetalGeometryReadU32LE(payload + 8);
                uint32_t h = OrenAVMMetalGeometryReadU32LE(payload + 12);
                uint32_t width = OrenAVMMetalGeometryReadU32LE(payload + 16);
                uint32_t flags = OrenAVMMetalGeometryReadU32LE(payload + 20);
                OrenAVMMetalRGBAWithOpacity(payload + 24, opacity, rgba);
                OrenAVMMetalAppendEllipse(vertices,
                                          (float)x + tx,
                                          (float)y + ty,
                                          (float)w,
                                          (float)h,
                                          (float)(width == 0 ? 1u : width),
                                          (flags & 1u) != 0,
                                          logicalWidth,
                                          logicalHeight,
                                          rgba);
            }
            return YES;
        }
        case 8: {
            if (payloadLen >= 28 && ((payloadLen - 12) % 8) == 0) {
                uint32_t width = OrenAVMMetalGeometryReadU32LE(payload);
                uint32_t pointCount = OrenAVMMetalGeometryReadU32LE(payload + 4);
                OrenAVMMetalRGBAWithOpacity(payload + 8, opacity, rgba);
                const uint8_t* points = payload + 12;
                if (pointCount == ((uint32_t)payloadLen - 12u) / 8u && pointCount >= 2) {
                    uint32_t lastX = OrenAVMMetalGeometryReadU32LE(points);
                    uint32_t lastY = OrenAVMMetalGeometryReadU32LE(points + 4);
                    for (uint32_t pi = 1; pi < pointCount; pi++) {
                        const uint8_t* point = points + ((size_t)pi * 8u);
                        uint32_t x = OrenAVMMetalGeometryReadU32LE(point);
                        uint32_t y = OrenAVMMetalGeometryReadU32LE(point + 4);
                        OrenAVMMetalAppendLine(vertices,
                                               (float)lastX + tx,
                                               (float)lastY + ty,
                                               (float)x + tx,
                                               (float)y + ty,
                                               (float)(width == 0 ? 1u : width),
                                               logicalWidth,
                                               logicalHeight,
                                               rgba);
                        lastX = x;
                        lastY = y;
                    }
                }
            }
            return YES;
        }
        case 9: {
            if (payloadLen == 32) {
                uint32_t x = OrenAVMMetalGeometryReadU32LE(payload);
                uint32_t y = OrenAVMMetalGeometryReadU32LE(payload + 4);
                uint32_t w = OrenAVMMetalGeometryReadU32LE(payload + 8);
                uint32_t h = OrenAVMMetalGeometryReadU32LE(payload + 12);
                uint32_t radius = OrenAVMMetalGeometryReadU32LE(payload + 16);
                uint32_t width = OrenAVMMetalGeometryReadU32LE(payload + 20);
                uint32_t flags = OrenAVMMetalGeometryReadU32LE(payload + 24);
                OrenAVMMetalRGBAWithOpacity(payload + 28, opacity, rgba);
                OrenAVMMetalAppendRoundRect(vertices,
                                            (float)x + tx,
                                            (float)y + ty,
                                            (float)w,
                                            (float)h,
                                            (float)radius,
                                            (float)(width == 0 ? 1u : width),
                                            (flags & 1u) != 0,
                                            logicalWidth,
                                            logicalHeight,
                                            rgba);
            }
            return YES;
        }
        case 10: {
            if (payloadLen >= 32 && ((payloadLen - 8) % 24) == 0) {
                uint32_t triangleCount = OrenAVMMetalGeometryReadU32LE(payload);
                OrenAVMMetalRGBAWithOpacity(payload + 4, opacity, rgba);
                const uint8_t* tris = payload + 8;
                if (triangleCount == ((uint32_t)payloadLen - 8u) / 24u) {
                    for (uint32_t ti = 0; ti < triangleCount; ti++) {
                        const uint8_t* tri = tris + ((size_t)ti * 24u);
                        OrenAVMMetalAppendTriangle(vertices,
                                                   (float)OrenAVMMetalGeometryReadU32LE(tri) + tx,
                                                   (float)OrenAVMMetalGeometryReadU32LE(tri + 4) + ty,
                                                   (float)OrenAVMMetalGeometryReadU32LE(tri + 8) + tx,
                                                   (float)OrenAVMMetalGeometryReadU32LE(tri + 12) + ty,
                                                   (float)OrenAVMMetalGeometryReadU32LE(tri + 16) + tx,
                                                   (float)OrenAVMMetalGeometryReadU32LE(tri + 20) + ty,
                                                   logicalWidth,
                                                   logicalHeight,
                                                   rgba);
                    }
                }
            }
            return YES;
        }
        default:
            return NO;
    }
}

#endif
