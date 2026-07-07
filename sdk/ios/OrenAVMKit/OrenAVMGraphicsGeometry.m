#import "OrenAVMGraphicsGeometry.h"

#if TARGET_OS_IPHONE

static uint32_t OrenAVMGfxGeometryReadU32LE(const uint8_t* p) {
    return (uint32_t)p[0] |
        ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) |
        ((uint32_t)p[3] << 24);
}

static void OrenAVMGfxGeometrySetFillColor(CGContextRef ctx, const uint8_t* rgba) {
    CGContextSetRGBFillColor(ctx,
                             (CGFloat)rgba[0] / 255.0,
                             (CGFloat)rgba[1] / 255.0,
                             (CGFloat)rgba[2] / 255.0,
                             (CGFloat)rgba[3] / 255.0);
}

static void OrenAVMGfxGeometrySetStrokeColor(CGContextRef ctx, const uint8_t* rgba) {
    CGContextSetRGBStrokeColor(ctx,
                               (CGFloat)rgba[0] / 255.0,
                               (CGFloat)rgba[1] / 255.0,
                               (CGFloat)rgba[2] / 255.0,
                               (CGFloat)rgba[3] / 255.0);
}

BOOL OrenAVMGfxDrawImmediatePrimitive(CGContextRef ctx,
                                      uint8_t opcode,
                                      const uint8_t* payload,
                                      uint16_t payloadLen) {
    if (!ctx || !payload) return NO;
    switch (opcode) {
        case 1: {
            if (payloadLen == 20) {
                uint32_t x = OrenAVMGfxGeometryReadU32LE(payload);
                uint32_t y = OrenAVMGfxGeometryReadU32LE(payload + 4);
                uint32_t w = OrenAVMGfxGeometryReadU32LE(payload + 8);
                uint32_t h = OrenAVMGfxGeometryReadU32LE(payload + 12);
                OrenAVMGfxGeometrySetFillColor(ctx, payload + 16);
                CGContextFillRect(ctx, CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h));
            }
            return YES;
        }
        case 3: {
            if (payloadLen == 24) {
                uint32_t x1 = OrenAVMGfxGeometryReadU32LE(payload);
                uint32_t y1 = OrenAVMGfxGeometryReadU32LE(payload + 4);
                uint32_t x2 = OrenAVMGfxGeometryReadU32LE(payload + 8);
                uint32_t y2 = OrenAVMGfxGeometryReadU32LE(payload + 12);
                uint32_t width = OrenAVMGfxGeometryReadU32LE(payload + 16);
                OrenAVMGfxGeometrySetStrokeColor(ctx, payload + 20);
                CGContextSetLineWidth(ctx, (CGFloat)(width == 0 ? 1u : width));
                CGContextMoveToPoint(ctx, (CGFloat)x1, (CGFloat)y1);
                CGContextAddLineToPoint(ctx, (CGFloat)x2, (CGFloat)y2);
                CGContextStrokePath(ctx);
            }
            return YES;
        }
        case 4: {
            if (payloadLen == 20) {
                uint32_t cx = OrenAVMGfxGeometryReadU32LE(payload);
                uint32_t cy = OrenAVMGfxGeometryReadU32LE(payload + 4);
                uint32_t radius = OrenAVMGfxGeometryReadU32LE(payload + 8);
                uint32_t flags = OrenAVMGfxGeometryReadU32LE(payload + 12);
                int32_t ox = (int32_t)cx - (int32_t)radius;
                int32_t oy = (int32_t)cy - (int32_t)radius;
                CGRect oval = CGRectMake((CGFloat)ox,
                                         (CGFloat)oy,
                                         (CGFloat)(radius * 2u),
                                         (CGFloat)(radius * 2u));
                if ((flags & 1u) != 0) {
                    OrenAVMGfxGeometrySetFillColor(ctx, payload + 16);
                    CGContextFillEllipseInRect(ctx, oval);
                } else {
                    OrenAVMGfxGeometrySetStrokeColor(ctx, payload + 16);
                    CGContextStrokeEllipseInRect(ctx, oval);
                }
            }
            return YES;
        }
        case 5: {
            if (payloadLen == 28) {
                uint32_t x1 = OrenAVMGfxGeometryReadU32LE(payload);
                uint32_t y1 = OrenAVMGfxGeometryReadU32LE(payload + 4);
                uint32_t x2 = OrenAVMGfxGeometryReadU32LE(payload + 8);
                uint32_t y2 = OrenAVMGfxGeometryReadU32LE(payload + 12);
                uint32_t x3 = OrenAVMGfxGeometryReadU32LE(payload + 16);
                uint32_t y3 = OrenAVMGfxGeometryReadU32LE(payload + 20);
                OrenAVMGfxGeometrySetFillColor(ctx, payload + 24);
                CGContextBeginPath(ctx);
                CGContextMoveToPoint(ctx, (CGFloat)x1, (CGFloat)y1);
                CGContextAddLineToPoint(ctx, (CGFloat)x2, (CGFloat)y2);
                CGContextAddLineToPoint(ctx, (CGFloat)x3, (CGFloat)y3);
                CGContextClosePath(ctx);
                CGContextFillPath(ctx);
            }
            return YES;
        }
        case 6: {
            if (payloadLen == 24) {
                uint32_t x = OrenAVMGfxGeometryReadU32LE(payload);
                uint32_t y = OrenAVMGfxGeometryReadU32LE(payload + 4);
                uint32_t w = OrenAVMGfxGeometryReadU32LE(payload + 8);
                uint32_t h = OrenAVMGfxGeometryReadU32LE(payload + 12);
                uint32_t width = OrenAVMGfxGeometryReadU32LE(payload + 16);
                OrenAVMGfxGeometrySetStrokeColor(ctx, payload + 20);
                CGContextStrokeRectWithWidth(ctx,
                                             CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h),
                                             (CGFloat)(width == 0 ? 1u : width));
            }
            return YES;
        }
        case 7: {
            if (payloadLen == 28) {
                uint32_t x = OrenAVMGfxGeometryReadU32LE(payload);
                uint32_t y = OrenAVMGfxGeometryReadU32LE(payload + 4);
                uint32_t w = OrenAVMGfxGeometryReadU32LE(payload + 8);
                uint32_t h = OrenAVMGfxGeometryReadU32LE(payload + 12);
                uint32_t width = OrenAVMGfxGeometryReadU32LE(payload + 16);
                uint32_t flags = OrenAVMGfxGeometryReadU32LE(payload + 20);
                CGRect oval = CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h);
                if ((flags & 1u) != 0) {
                    OrenAVMGfxGeometrySetFillColor(ctx, payload + 24);
                    CGContextFillEllipseInRect(ctx, oval);
                } else {
                    OrenAVMGfxGeometrySetStrokeColor(ctx, payload + 24);
                    CGContextSetLineWidth(ctx, (CGFloat)(width == 0 ? 1u : width));
                    CGContextStrokeEllipseInRect(ctx, oval);
                }
            }
            return YES;
        }
        case 8: {
            if (payloadLen >= 28 && ((payloadLen - 12u) % 8u) == 0) {
                uint32_t width = OrenAVMGfxGeometryReadU32LE(payload);
                uint32_t pointCount = OrenAVMGfxGeometryReadU32LE(payload + 4);
                if (pointCount == ((uint32_t)payloadLen - 12u) / 8u && pointCount >= 2) {
                    OrenAVMGfxGeometrySetStrokeColor(ctx, payload + 8);
                    CGContextSetLineWidth(ctx, (CGFloat)(width == 0 ? 1u : width));
                    const uint8_t* points = payload + 12;
                    CGContextBeginPath(ctx);
                    CGContextMoveToPoint(ctx,
                                         (CGFloat)OrenAVMGfxGeometryReadU32LE(points),
                                         (CGFloat)OrenAVMGfxGeometryReadU32LE(points + 4));
                    for (uint32_t pi = 1; pi < pointCount; pi++) {
                        const uint8_t* point = points + ((size_t)pi * 8u);
                        CGContextAddLineToPoint(ctx,
                                                (CGFloat)OrenAVMGfxGeometryReadU32LE(point),
                                                (CGFloat)OrenAVMGfxGeometryReadU32LE(point + 4));
                    }
                    CGContextStrokePath(ctx);
                }
            }
            return YES;
        }
        case 9: {
            if (payloadLen == 32) {
                uint32_t x = OrenAVMGfxGeometryReadU32LE(payload);
                uint32_t y = OrenAVMGfxGeometryReadU32LE(payload + 4);
                uint32_t w = OrenAVMGfxGeometryReadU32LE(payload + 8);
                uint32_t h = OrenAVMGfxGeometryReadU32LE(payload + 12);
                uint32_t radius = OrenAVMGfxGeometryReadU32LE(payload + 16);
                uint32_t width = OrenAVMGfxGeometryReadU32LE(payload + 20);
                uint32_t flags = OrenAVMGfxGeometryReadU32LE(payload + 24);
                UIBezierPath* path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h)
                                                                 cornerRadius:(CGFloat)radius];
                if ((flags & 1u) != 0) {
                    OrenAVMGfxGeometrySetFillColor(ctx, payload + 28);
                    [path fill];
                } else {
                    OrenAVMGfxGeometrySetStrokeColor(ctx, payload + 28);
                    path.lineWidth = (CGFloat)(width == 0 ? 1u : width);
                    [path stroke];
                }
            }
            return YES;
        }
        case 10: {
            if (payloadLen >= 32 && ((payloadLen - 8u) % 24u) == 0) {
                uint32_t triangleCount = OrenAVMGfxGeometryReadU32LE(payload);
                const uint8_t* tris = payload + 8;
                if (triangleCount == ((uint32_t)payloadLen - 8u) / 24u) {
                    OrenAVMGfxGeometrySetFillColor(ctx, payload + 4);
                    for (uint32_t ti = 0; ti < triangleCount; ti++) {
                        const uint8_t* tri = tris + ((size_t)ti * 24u);
                        CGContextBeginPath(ctx);
                        CGContextMoveToPoint(ctx,
                                             (CGFloat)OrenAVMGfxGeometryReadU32LE(tri),
                                             (CGFloat)OrenAVMGfxGeometryReadU32LE(tri + 4));
                        CGContextAddLineToPoint(ctx,
                                                (CGFloat)OrenAVMGfxGeometryReadU32LE(tri + 8),
                                                (CGFloat)OrenAVMGfxGeometryReadU32LE(tri + 12));
                        CGContextAddLineToPoint(ctx,
                                                (CGFloat)OrenAVMGfxGeometryReadU32LE(tri + 16),
                                                (CGFloat)OrenAVMGfxGeometryReadU32LE(tri + 20));
                        CGContextClosePath(ctx);
                        CGContextFillPath(ctx);
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
