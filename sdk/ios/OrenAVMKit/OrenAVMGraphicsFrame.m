#import "OrenAVMGraphicsFrame.h"

#if TARGET_OS_IPHONE

#import "OrenAVMGraphicsGeometry.h"
#import "OrenAVMGraphicsResources.h"
#include <string.h>

static uint32_t OrenAVMGfxFrameRGBAValue(const uint8_t* rgba) {
    return (uint32_t)rgba[0] |
        ((uint32_t)rgba[1] << 8) |
        ((uint32_t)rgba[2] << 16) |
        ((uint32_t)rgba[3] << 24);
}

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
        } else if (opcode == 80 && payloadLen >= 36 && ((payloadLen - 12) % 24) == 0) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t triangleCount = OrenAVMGfxReadU32LE(payload + 8);
            if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 12u) / 24u) {
                (void)OrenAVMGfxPutTriangleMeshResource(context->meshes,
                                                        meshID,
                                                        OrenAVMGfxFrameRGBAValue(payload + 4),
                                                        payload + 12,
                                                        (NSUInteger)payloadLen - 12u,
                                                        triangleCount,
                                                        24u,
                                                        NO);
            }
        } else if (opcode == 81 && payloadLen == 4) {
            OrenAVMGfxDrawMesh2DResource(ctx, context->meshes ? *context->meshes : NULL, OrenAVMGfxReadU32LE(payload));
        } else if (opcode == 82 && payloadLen == 4) {
            OrenAVMGfxRemoveMeshResource(context->meshes ? *context->meshes : NULL, OrenAVMGfxReadU32LE(payload));
        } else if (opcode == 83 && payloadLen >= 48 && ((payloadLen - 12) % 36) == 0) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t triangleCount = OrenAVMGfxReadU32LE(payload + 8);
            if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 12u) / 36u) {
                (void)OrenAVMGfxPutTriangleMeshResource(context->meshes,
                                                        meshID,
                                                        OrenAVMGfxFrameRGBAValue(payload + 4),
                                                        payload + 12,
                                                        (NSUInteger)payloadLen - 12u,
                                                        triangleCount,
                                                        36u,
                                                        NO);
            }
        } else if ((opcode == 84 && payloadLen == 4) || (opcode == 87 && payloadLen == 20) ||
                   (opcode == 90 && payloadLen == 8) || (opcode == 91 && payloadLen == 24) ||
                   (opcode == 94 && payloadLen == 4)) {
            OrenAVMGfxDrawMesh3DResource(ctx,
                                         context->meshes ? *context->meshes : NULL,
                                         context->materials3D ? *context->materials3D : NULL,
                                         context->models3D ? *context->models3D : NULL,
                                         opcode,
                                         payload,
                                         frameState.depthEnabled,
                                         frameState.nearZ,
                                         frameState.farZ);
        } else if (opcode == 85 && payloadLen == 4) {
            OrenAVMGfxRemoveMeshResource(context->meshes ? *context->meshes : NULL, OrenAVMGfxReadU32LE(payload));
        } else if (opcode == 89 && payloadLen == 8) {
            uint32_t materialID = OrenAVMGfxReadU32LE(payload);
            (void)OrenAVMGfxPutMaterialResource(context->materials3D, materialID, OrenAVMGfxFrameRGBAValue(payload + 4));
        } else if (opcode == 92 && payloadLen == 4) {
            OrenAVMGfxRemoveMaterialResource(context->materials3D ? *context->materials3D : NULL, OrenAVMGfxReadU32LE(payload));
        } else if (opcode == 93 && payloadLen == 28) {
            uint32_t modelID = OrenAVMGfxReadU32LE(payload);
            uint32_t meshID = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t scaleMilli = OrenAVMGfxReadU32LE(payload + 24);
            (void)OrenAVMGfxPutModelResource(context->models3D,
                                             modelID,
                                             meshID,
                                             OrenAVMGfxReadU32LE(payload + 8),
                                             (int32_t)OrenAVMGfxReadU32LE(payload + 12),
                                             (int32_t)OrenAVMGfxReadU32LE(payload + 16),
                                             (int32_t)OrenAVMGfxReadU32LE(payload + 20),
                                             scaleMilli);
        } else if (opcode == 95 && payloadLen == 4) {
            OrenAVMGfxRemoveModelResource(context->models3D ? *context->models3D : NULL, OrenAVMGfxReadU32LE(payload));
        } else if (opcode == 86 && payloadLen >= 48 && ((payloadLen - 8) % 40) == 0) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t triangleCount = OrenAVMGfxReadU32LE(payload + 4);
            if (meshID != 0 && triangleCount == ((uint32_t)payloadLen - 8u) / 40u) {
                (void)OrenAVMGfxPutTriangleMeshResource(context->meshes,
                                                        meshID,
                                                        0,
                                                        payload + 8,
                                                        (NSUInteger)payloadLen - 8u,
                                                        triangleCount,
                                                        40u,
                                                        YES);
            }
        } else if (opcode == 88 && payloadLen >= 64) {
            uint32_t meshID = OrenAVMGfxReadU32LE(payload);
            uint32_t vertexCount = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t indexCount = OrenAVMGfxReadU32LE(payload + 12);
            size_t vertexBytes = (size_t)vertexCount * 12u;
            size_t indexBytes = (size_t)indexCount * 4u;
            if (16u + vertexBytes + indexBytes == (size_t)payloadLen) {
                (void)OrenAVMGfxPutIndexedMeshResource(context->meshes,
                                                       meshID,
                                                       OrenAVMGfxFrameRGBAValue(payload + 4),
                                                       payload + 16,
                                                       vertexBytes,
                                                       vertexCount,
                                                       payload + 16 + vertexBytes,
                                                       indexBytes,
                                                       indexCount);
            }
        } else if (opcode == 2 && payloadLen >= 16) {
            uint32_t x = OrenAVMGfxReadU32LE(payload);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t textLen = OrenAVMGfxReadU32LE(payload + 12);
            if (textLen <= (uint32_t)payloadLen - 16u) {
                NSDictionary<NSAttributedStringKey, id>* attrs = OrenAVMGfxTextAttributesForRGBA(context->textAttributes,
                                                                                                  context->lastTextAttributesRGBA,
                                                                                                  context->lastTextAttributes,
                                                                                                  OrenAVMGfxFrameRGBAValue(payload + 8));
                OrenAVMGfxDrawTextBytes(payload + 16, textLen, x, y, attrs);
            }
        } else if (opcode == 68 && payloadLen >= 12) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            uint32_t textLen = OrenAVMGfxReadU32LE(payload + 8);
            if (textLen == (uint32_t)payloadLen - 12u) {
                NSDictionary<NSAttributedStringKey, id>* attrs = OrenAVMGfxTextAttributesForRGBA(context->textAttributes,
                                                                                                  context->lastTextAttributesRGBA,
                                                                                                  context->lastTextAttributes,
                                                                                                  OrenAVMGfxFrameRGBAValue(payload + 4));
                (void)OrenAVMGfxPutTextResource(context->textResources, textID, payload + 12, textLen, attrs);
            }
        } else if (opcode == 69 && payloadLen == 12) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            uint32_t x = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 8);
            OrenAVMGfxDrawTextResource(context->textResources ? *context->textResources : NULL, textID, x, y);
        } else if (opcode == 72 && payloadLen >= 16 && ((payloadLen - 8) % 8) == 0) {
            uint32_t textID = OrenAVMGfxReadU32LE(payload);
            uint32_t posCount = OrenAVMGfxReadU32LE(payload + 4);
            if (posCount == ((uint32_t)payloadLen - 8u) / 8u) {
                OrenAVMGfxDrawTextResourcePositions(context->textResources ? *context->textResources : NULL, textID, payload + 8, posCount);
            }
        } else if (opcode == 70 && payloadLen == 4) {
            OrenAVMGfxRemoveTextResource(context->textResources ? *context->textResources : NULL, OrenAVMGfxReadU32LE(payload));
        } else if (opcode == 64 && payloadLen >= 16) {
            uint32_t imageID = OrenAVMGfxReadU32LE(payload);
            uint32_t iw = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t ih = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t imageLen = OrenAVMGfxReadU32LE(payload + 12);
            if (imageLen == (uint32_t)payloadLen - 16u) {
                UIImage* image = OrenAVMGfxImageRGBA(payload + 16, iw, ih, imageLen);
                (void)OrenAVMGfxPutImageResource(context->images,
                                                 image,
                                                 imageID,
                                                 (NSUInteger)iw * (NSUInteger)ih,
                                                 context->retainedImageCountLimit,
                                                 context->retainedImagePixelLimit,
                                                 context->retainedImagePixelCount);
            }
        } else if (opcode == 65 && payloadLen == 20) {
            uint32_t imageID = OrenAVMGfxReadU32LE(payload);
            uint32_t x = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t w = OrenAVMGfxReadU32LE(payload + 12);
            uint32_t h = OrenAVMGfxReadU32LE(payload + 16);
            UIImage* image = OrenAVMGfxRetainedImageResource(context->images ? *context->images : NULL, imageID).image;
            if (image) [image drawInRect:CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h)];
        } else if (opcode == 66 && payloadLen == 4) {
            OrenAVMGfxRemoveImageResource(context->images ? *context->images : NULL, OrenAVMGfxReadU32LE(payload), context->retainedImagePixelCount);
        } else if (opcode == 67 && payloadLen == 36) {
            uint32_t imageID = OrenAVMGfxReadU32LE(payload);
            uint32_t sx = OrenAVMGfxReadU32LE(payload + 4);
            uint32_t sy = OrenAVMGfxReadU32LE(payload + 8);
            uint32_t sw = OrenAVMGfxReadU32LE(payload + 12);
            uint32_t sh = OrenAVMGfxReadU32LE(payload + 16);
            uint32_t x = OrenAVMGfxReadU32LE(payload + 20);
            uint32_t y = OrenAVMGfxReadU32LE(payload + 24);
            uint32_t w = OrenAVMGfxReadU32LE(payload + 28);
            uint32_t h = OrenAVMGfxReadU32LE(payload + 32);
            UIImage* image = OrenAVMGfxRetainedImageResource(context->images ? *context->images : NULL, imageID).image;
            CGImageRef cgImage = image.CGImage;
            if (cgImage) {
                OrenAVMGfxDrawImageSubrect(cgImage, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage),
                                           sx, sy, sw, sh, x, y, w, h);
            }
        } else if (opcode == 71 && payloadLen >= 40 && ((payloadLen - 8) % 32) == 0) {
            uint32_t imageID = OrenAVMGfxReadU32LE(payload);
            uint32_t rectCount = OrenAVMGfxReadU32LE(payload + 4);
            UIImage* image = OrenAVMGfxRetainedImageResource(context->images ? *context->images : NULL, imageID).image;
            CGImageRef cgImage = image.CGImage;
            if (cgImage && rectCount == ((uint32_t)payloadLen - 8u) / 32u) {
                size_t imageWidth = CGImageGetWidth(cgImage);
                size_t imageHeight = CGImageGetHeight(cgImage);
                for (uint32_t ri = 0; ri < rectCount; ri++) {
                    const uint8_t* r = payload + 8 + ((size_t)ri * 32u);
                    uint32_t sx = OrenAVMGfxReadU32LE(r);
                    uint32_t sy = OrenAVMGfxReadU32LE(r + 4);
                    uint32_t sw = OrenAVMGfxReadU32LE(r + 8);
                    uint32_t sh = OrenAVMGfxReadU32LE(r + 12);
                    uint32_t x = OrenAVMGfxReadU32LE(r + 16);
                    uint32_t y = OrenAVMGfxReadU32LE(r + 20);
                    uint32_t w = OrenAVMGfxReadU32LE(r + 24);
                    uint32_t h = OrenAVMGfxReadU32LE(r + 28);
                    OrenAVMGfxDrawImageSubrect(cgImage, imageWidth, imageHeight, sx, sy, sw, sh, x, y, w, h);
                }
            }
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
                }
            }
            return YES;
        }
        case 21: {
            if (payloadLen == 0 && state->opacityDepth > 0 && state->stateDepth > 0) {
                CGContextRestoreGState(ctx);
                state->opacity = state->opacityStack[--state->opacityDepth];
                state->stateDepth--;
            }
            return YES;
        }
        case 22: {
            if (payloadLen == 8 && state->cameraDepth < 64) {
                state->depthEnabledStack[state->cameraDepth] = state->depthEnabled;
                state->nearZStack[state->cameraDepth] = state->nearZ;
                state->farZStack[state->cameraDepth] = state->farZ;
                state->cameraDepth++;
                state->depthEnabled = YES;
                state->nearZ = (int32_t)OrenAVMGfxReadU32LE(payload);
                state->farZ = (int32_t)OrenAVMGfxReadU32LE(payload + 4);
                state->stateDepth++;
            }
            return YES;
        }
        case 23: {
            if (payloadLen == 0 && state->cameraDepth > 0 && state->stateDepth > 0) {
                state->cameraDepth--;
                state->depthEnabled = state->depthEnabledStack[state->cameraDepth];
                state->nearZ = state->nearZStack[state->cameraDepth];
                state->farZ = state->farZStack[state->cameraDepth];
                state->stateDepth--;
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
