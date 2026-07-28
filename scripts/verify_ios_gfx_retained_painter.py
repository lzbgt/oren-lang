#!/usr/bin/env python3
"""Verify retained 3D fallback painter ordering stays on compact buffers."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsView.m"
FRAME_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsFrame.h"
FRAME_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsFrame.m"
GEOMETRY_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsGeometry.h"
GEOMETRY_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsGeometry.m"
RESOURCE_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsResources.h"
RESOURCE_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsResources.m"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def require_before(block: str, before: str, after: str, message: str) -> None:
    before_pos = block.find(before)
    after_pos = block.find(after)
    if before_pos < 0 or after_pos < 0 or before_pos > after_pos:
        fail(message)


def main() -> int:
    view_text = SOURCE.read_text()
    frame_header_text = FRAME_HEADER.read_text()
    frame_text = FRAME_SOURCE.read_text()
    geometry_text = GEOMETRY_HEADER.read_text() + "\n" + GEOMETRY_SOURCE.read_text()
    resource_source_text = RESOURCE_SOURCE.read_text()
    resource_text = RESOURCE_HEADER.read_text() + "\n" + resource_source_text
    frame_command_text = frame_text
    text = view_text + "\n" + frame_header_text + "\n" + frame_text + "\n" + geometry_text + "\n" + resource_text
    required = [
        "OrenAVMGfxTriangleOrder",
        "OrenAVMGfxTriangleOrderAppend",
        "OrenAVMGfxSortTriangleOrder",
    ]
    for token in required:
        if token not in text:
            fail(f"missing retained 3D painter helper: {token}")
    if "NSMutableSet<NSNumber*>* drawn" in text or "[drawn containsObject:" in text:
        fail("retained 3D painter path still uses boxed set tracking")
    if text.count("OrenAVMGfxSortTriangleOrder(order, visibleCount)") < 2:
        fail("expected sorted order path for indexed and packed retained 3D meshes")
    if text.count("if (visibleCount == 0) {\n            free(heapOrder);\n            return;\n        }") < 2:
        fail("CoreGraphics retained 3D draw paths must skip sort/color work when all triangles are clipped")
    if "OrenAVMGfxInlineTriangleOrderCapacity = 128" not in text:
        fail("CoreGraphics retained 3D triangle ordering must have a small stack buffer")
    if "static BOOL OrenAVMGfxTriangleOrderAppend" not in resource_text:
        fail("CoreGraphics retained 3D triangle ordering helper must append visible triangles in OrenAVMGraphicsResources")
    if "OrenAVMGfxTriangleOrderBuffer(triangleCount" in text:
        fail("CoreGraphics retained 3D triangle ordering must not allocate order storage for fully clipped triangles")
    if text.count("OrenAVMGfxTriangleOrder inlineOrder[OrenAVMGfxInlineTriangleOrderCapacity]") < 2:
        fail("CoreGraphics retained 3D draw paths must pass stack triangle-order buffers")
    if "NSMutableData* orderData" in text or "dataWithLength:(NSUInteger)triangleCount * sizeof(OrenAVMGfxTriangleOrder)" in text:
        fail("CoreGraphics retained 3D triangle ordering must not use NSMutableData heap fallbacks")
    if "OrenAVMGfxTriangleOrder* heapOrder = NULL" not in text or "free(heapOrder)" not in text:
        fail("CoreGraphics retained 3D triangle ordering must free raw heap fallbacks")
    if "order[visibleCount++] = (OrenAVMGfxTriangleOrder)" in text:
        fail("CoreGraphics retained 3D draw paths must grow order storage as visible triangles are appended")
    if "@interface OrenAVMGfxMeshResource" not in text:
        fail("CoreGraphics retained meshes must use typed resource objects")
    if "static UIColor* OrenAVMGfxColor(const uint8_t* rgba)" in text:
        fail("CoreGraphics immediate primitive colors must not allocate UIColor wrappers")
    if "CGContextSetFillColorWithColor(ctx, color.CGColor)" in text or "CGContextSetStrokeColorWithColor(ctx, color.CGColor)" in text:
        fail("CoreGraphics immediate primitive colors must use direct byte/scalar setters")
    if "OrenAVMGfxGeometrySetFillColor(ctx, payload + 16)" not in geometry_text or "OrenAVMGfxGeometrySetStrokeColor(ctx, payload + 20)" not in geometry_text:
        fail("CoreGraphics immediate primitive color fast path is missing")
    if 'NSMutableDictionary<NSNumber*, NSDictionary<NSString*, id>*>* orenMeshes' in text:
        fail("CoreGraphics retained meshes must not use dictionary payload records")
    if "NSMutableDictionary<NSNumber*, OrenAVMGfxMeshResource*>* orenMeshes" in text:
        fail("CoreGraphics retained mesh lookups must avoid boxed NSNumber mesh IDs")
    if "CFMutableDictionaryRef _orenMeshesByID" not in text:
        fail("CoreGraphics retained mesh resources must use a scalar-key CF dictionary")
    if "OrenAVMGfxRetainedMeshResource(meshes, meshID)" not in resource_text:
        fail("CoreGraphics retained 3D mesh draws must use the scalar-map resource helper")
    if "OrenAVMGfxHandleMeshCommand(ctx," not in frame_command_text:
        fail("CoreGraphics frame traversal must delegate retained mesh opcodes to OrenAVMGraphicsResources")
    for token in (
        "static BOOL OrenAVMGfxClipIsEmpty(CGContextRef ctx, BOOL alreadyEmpty)",
        "static BOOL OrenAVMGfxOpcodeIsDrawOnly(uint8_t opcode)",
        "BOOL clipEmpty;",
        "BOOL clipEmptyStack[OrenAVMGfxFrameStateStackCapacity];",
        "case 1:",
        "case 2:",
        "case 65:",
        "case 72:",
        "case 81:",
        "case 94:",
    ):
        if token not in text:
            fail(f"CoreGraphics elided draw skip missing expected coverage: {token}")
    draw_frame_start = frame_text.find("void OrenAVMGfxDrawFrame")
    state_handler_start = frame_text.find("BOOL OrenAVMGfxHandleFrameStateCommand", draw_frame_start)
    draw_frame_body = frame_text[draw_frame_start:state_handler_start]
    require_before(draw_frame_body,
                   "OrenAVMGfxHandleFrameStateCommand(ctx, opcode, payload, payloadLen, &frameState)",
                   "(frameState.clipEmpty || frameState.opacity <= 0.0) && OrenAVMGfxOpcodeIsDrawOnly(opcode)",
                   "CoreGraphics frame traversal must handle state before empty-clip/transparent draw skips")
    require_before(draw_frame_body,
                   "(frameState.clipEmpty || frameState.opacity <= 0.0) && OrenAVMGfxOpcodeIsDrawOnly(opcode)",
                   "OrenAVMGfxDrawImmediatePrimitive(ctx, opcode, payload, payloadLen)",
                   "CoreGraphics frame traversal must skip elided draws before immediate primitive work")
    if "OrenAVMGfxDrawMesh3DResource(ctx," not in resource_text:
        fail("CoreGraphics retained 3D mesh draws must live in OrenAVMGraphicsResources")
    if "void OrenAVMGfxDrawMesh3DResource(CGContextRef ctx," not in resource_text:
        fail("CoreGraphics retained 3D mesh draw helper must live in OrenAVMGraphicsResources")
    if "OrenAVMGfxPutTriangleMeshResource(meshes," not in resource_text:
        fail("CoreGraphics retained triangle mesh uploads must live in OrenAVMGraphicsResources")
    if "OrenAVMGfxPutIndexedMeshResource(meshes," not in resource_text:
        fail("CoreGraphics retained indexed mesh uploads must live in OrenAVMGraphicsResources")
    if "OrenAVMGfxRemoveMeshResource(meshes ? *meshes : NULL" not in resource_text:
        fail("CoreGraphics retained mesh removals must live in OrenAVMGraphicsResources")
    if "CFDictionarySetValue(_orenMeshesByID" in view_text or "CFDictionaryRemoveValue(_orenMeshesByID" in view_text:
        fail("CoreGraphics view must not mutate retained mesh maps directly")
    if "OrenAVMGfxDrawMesh2DResource(ctx, meshes ? *meshes : NULL" not in resource_text:
        fail("CoreGraphics retained 2D mesh draws must live in OrenAVMGraphicsResources")
    if "void OrenAVMGfxDrawMesh2DResource(CGContextRef ctx, CFDictionaryRef meshes, uint32_t meshID, CGFloat opacity)" not in resource_text:
        fail("CoreGraphics retained 2D mesh draw helper must live in OrenAVMGraphicsResources")
    if "mesh.triangleCount != mesh.triangleBytes / 24u" not in resource_text:
        fail("CoreGraphics retained 2D mesh draw helper must validate the raw 2D triangle payload")
    mesh2d_draw_start = resource_source_text.find("void OrenAVMGfxDrawMesh2DResource(CGContextRef ctx,")
    mesh2d_draw_end = resource_source_text.find("void OrenAVMGfxDrawMesh3DResource(CGContextRef ctx,", mesh2d_draw_start)
    if mesh2d_draw_start < 0 or mesh2d_draw_end < 0:
        fail("missing CoreGraphics retained 2D mesh draw helper block")
    mesh2d_draw_body = resource_source_text[mesh2d_draw_start:mesh2d_draw_end]
    if "if (!ctx || opacity <= 0.0) return;" not in mesh2d_draw_body:
        fail("CoreGraphics retained 2D mesh draws must skip fully transparent work before retained lookup")
    if "OrenAVMGfxHandleMeshCommand(ctx," not in frame_text or "frameState.opacity" not in frame_text:
        fail("CoreGraphics frame traversal must pass opacity into retained mesh command handling")
    if "const uint8_t* tri = tris + ((size_t)ti * 24u)" in frame_command_text:
        fail("CoreGraphics frame traversal must not expand retained 2D mesh triangle payloads directly")
    if "@property(nonatomic, strong) NSData* triangles" in text or "@property(nonatomic, strong) NSData* indices" in text:
        fail("CoreGraphics retained mesh payloads must stay raw owned buffers, not NSData wrappers")
    for pattern in (
        "mesh.triangles = [NSData dataWithBytes:payload",
        "mesh.vertices = [NSData dataWithBytes:payload",
        "mesh.indices = [NSData dataWithBytes:payload",
        "mesh.triangles.bytes",
        "mesh.indices.length",
    ):
        if pattern in text:
            fail("CoreGraphics retained mesh payload path regressed to NSData-backed access")
    if "OrenAVMGfxCopyPayloadBytes" not in text:
        fail("missing CoreGraphics retained mesh raw payload copy helper")
    if "if (!src || len == 0) return NULL;" not in resource_text:
        fail("CoreGraphics retained mesh payload copy helper must reject null sources before memcpy")
    put_text_start = resource_source_text.find("BOOL OrenAVMGfxPutTextResource")
    put_text_end = resource_source_text.find("void OrenAVMGfxDrawTextResource", put_text_start)
    if put_text_start < 0 or put_text_end < 0:
        fail("missing CoreGraphics retained text upload helper")
    put_text_body = resource_source_text[put_text_start:put_text_end]
    if "if (!texts || textID == 0 || !textBytes || textLen == 0 || !attrs) return NO;" not in put_text_body:
        fail("CoreGraphics retained text uploads must reject empty text before map/string/resource work")
    require_before(put_text_body,
                   "OrenAVMGfxEnsureRetainedResourceMap(texts)",
                   "[[NSString alloc] initWithBytes:textBytes",
                   "CoreGraphics retained text uploads must preflight scalar-map storage before string creation")
    require_before(put_text_body,
                   "OrenAVMGfxEnsureRetainedResourceMap(texts)",
                   "[[OrenAVMGfxTextResource alloc] init]",
                   "CoreGraphics retained text uploads must preflight scalar-map storage before resource allocation")
    require_before(put_text_body,
                   "if (!resource) return NO;",
                   "CFDictionarySetValue(*texts",
                   "CoreGraphics retained text uploads must guard resource allocation before map insertion")
    put_triangle_start = resource_source_text.find("BOOL OrenAVMGfxPutTriangleMeshResource")
    put_indexed_start = resource_source_text.find("BOOL OrenAVMGfxPutIndexedMeshResource", put_triangle_start)
    put_mesh_end = resource_source_text.find("void OrenAVMGfxRemoveMeshResource", put_indexed_start)
    if put_triangle_start < 0 or put_indexed_start < 0 or put_mesh_end < 0:
        fail("missing CoreGraphics retained mesh upload helpers")
    put_triangle_body = resource_source_text[put_triangle_start:put_indexed_start]
    put_indexed_body = resource_source_text[put_indexed_start:put_mesh_end]
    require_before(put_triangle_body,
                   "OrenAVMGfxEnsureRetainedResourceMap(meshes)",
                   "OrenAVMGfxCopyPayloadBytes(triangles, triangleBytes)",
                   "CoreGraphics retained triangle mesh uploads must preflight scalar-map storage before payload copies")
    require_before(put_indexed_body,
                   "OrenAVMGfxEnsureRetainedResourceMap(meshes)",
                   "OrenAVMGfxCopyPayloadBytes(vertices, vertexBytes)",
                   "CoreGraphics retained indexed mesh uploads must preflight scalar-map storage before payload copies")
    for token in (
        "uint8_t* triangleCopy = OrenAVMGfxCopyPayloadBytes(triangles, triangleBytes);",
        "mesh.triangles = triangleCopy;",
        "uint8_t* vertexCopy = OrenAVMGfxCopyPayloadBytes(vertices, vertexBytes);",
        "if (!vertexCopy) return NO;",
        "uint8_t* indexCopy = OrenAVMGfxCopyPayloadBytes(indices, indexBytes);",
        "if (!indexCopy) {\n        free(vertexCopy);\n        return NO;\n    }",
        "mesh.vertices = vertexCopy;",
        "mesh.indices = indexCopy;",
    ):
        if token not in resource_text:
            fail(f"CoreGraphics retained mesh payload copies must be staged and checked before resource install: {token}")
    for pattern in (
        "mesh.triangles = OrenAVMGfxCopyPayloadBytes(triangles, triangleBytes);",
        "mesh.vertices = OrenAVMGfxCopyPayloadBytes(vertices, mesh.vertexBytes);",
        "mesh.indices = OrenAVMGfxCopyPayloadBytes(indices, mesh.indexBytes);",
    ):
        if pattern in resource_text:
            fail("CoreGraphics retained mesh payload path must not assign unchecked direct copy results")
    if "NSMutableDictionary<NSNumber*, UIColor*>* orenMaterials3D" in text:
        fail("CoreGraphics retained materials must store scalar RGBA values")
    if "NSMutableDictionary<NSNumber*, NSNumber*>* orenMaterials3D" in text:
        fail("CoreGraphics retained materials must avoid boxed NSNumber IDs/RGBA values")
    if "CFMutableDictionaryRef _orenMaterials3DByID" not in text:
        fail("CoreGraphics retained materials must use a scalar-key/scalar-value CF dictionary")
    if "OrenAVMGfxRetainedMaterialRGBA(materials, materialID, &materialRGBAOverride)" not in resource_text:
        fail("CoreGraphics retained material draws must use the scalar material lookup helper")
    if "OrenAVMGfxPutMaterialResource(materials, materialID" not in resource_text:
        fail("CoreGraphics retained material uploads must live in OrenAVMGraphicsResources")
    if "OrenAVMGfxRemoveMaterialResource(materials ? *materials : NULL" not in resource_text:
        fail("CoreGraphics retained material removals must live in OrenAVMGraphicsResources")
    if "CFDictionarySetValue(_orenMaterials3DByID" in view_text or "CFDictionaryRemoveValue(_orenMaterials3DByID" in view_text:
        fail("CoreGraphics view must not mutate retained material maps directly")
    if "materialRGBAValue" in text or "@(materialID)" in text:
        fail("CoreGraphics retained material paths must not box material IDs or RGBA values")
    if '@"color": OrenAVMGfxColor' in text:
        fail("CoreGraphics retained mesh colors must stay scalar, not retained UIColor objects")
    if "@interface OrenAVMGfxTextResource" not in text:
        fail("CoreGraphics retained text must use typed resource objects")
    if 'NSMutableDictionary<NSNumber*, NSDictionary<NSString*, id>*>* orenTextResources' in text:
        fail("CoreGraphics retained text must not use dictionary payload records")
    if 'NSMutableDictionary<NSNumber*, OrenAVMGfxTextResource*>* orenTextResources' in text:
        fail("CoreGraphics retained text lookups must avoid boxed NSNumber text IDs")
    if "CFMutableDictionaryRef _orenTextResourcesByID" not in text:
        fail("CoreGraphics retained text resources must use a scalar-key CF dictionary")
    if "OrenAVMGfxRetainedTextResource(texts, textID)" not in resource_text:
        fail("CoreGraphics retained text draws must use the typed scalar-map resource helper")
    for token in (
        "static BOOL OrenAVMGfxImageDimensions",
        "uint64_t heightByteFactor = (uint64_t)height * 4ull;",
        "if ((uint64_t)width > UINT64_MAX / heightByteFactor) return NO;",
        "if (expected != (uint64_t)byteCount || pixel64 > (uint64_t)NSUIntegerMax) return NO;",
        "if (!rgba || !OrenAVMGfxImageDimensions(width, height, byteCount, NULL)) return nil;",
        "if (!OrenAVMGfxImageDimensions(width, height, byteCount, &pixels)) return NO;",
    ):
        if token not in resource_text:
            fail(f"CoreGraphics retained image dimensions must be overflow-checked before allocation: {token}")
    if "OrenAVMGfxHandleTextCommand(ctx," not in frame_command_text:
        fail("CoreGraphics frame traversal must delegate retained text opcodes to OrenAVMGraphicsResources")
    if "OrenAVMGfxDrawTextResource(texts ? *texts : NULL, textID, x, y)" not in resource_text:
        fail("CoreGraphics retained text draws must live in OrenAVMGraphicsResources")
    if "OrenAVMGfxDrawTextResourcePositions(texts ? *texts : NULL, textID, payload + 8, posCount)" not in resource_text:
        fail("CoreGraphics retained text batched draws must live in OrenAVMGraphicsResources")
    handle_text_start = resource_source_text.find("BOOL OrenAVMGfxHandleTextCommand")
    handle_text_end = resource_source_text.find("BOOL OrenAVMGfxHandleMeshCommand", handle_text_start)
    if handle_text_start < 0 or handle_text_end < 0:
        fail("missing CoreGraphics text command helper")
    handle_text_body = resource_source_text[handle_text_start:handle_text_end]
    if "OrenAVMGfxDrawTextBytes" in resource_text:
        fail("CoreGraphics immediate text draws must stay localized in the command helper")
    if "if (textLen == (uint32_t)payloadLen - 16u && textLen > 0)" not in handle_text_body:
        fail("CoreGraphics immediate text opcodes must reject trailing payload bytes and empty text before attribute lookup")
    require_before(handle_text_body,
                   "if (!text) return YES;",
                   "OrenAVMGfxTextAttributesForRGBA(attrsByRGBA",
                   "CoreGraphics immediate text must reject invalid UTF-8 before attribute lookup")
    if "if (textLen == (uint32_t)payloadLen - 12u && textLen > 0)" not in handle_text_body:
        fail("CoreGraphics retained text upload opcodes must reject empty text before attribute lookup")
    if "if (textLen <= (uint32_t)payloadLen - 16u)" in handle_text_body:
        fail("CoreGraphics immediate text opcodes must not accept trailing payload bytes")
    if "@(textID)" in text:
        fail("CoreGraphics retained text upload/draw paths must not box text IDs")
    if 'self.orenTextResources[@(textID)] = @{@"text": text, @"color": color}' in text:
        fail("CoreGraphics retained text must cache typed attributed text")
    if "resource.attributes" in text or "@property(nonatomic, strong) NSDictionary<NSAttributedStringKey, id>* attributes" in text:
        fail("CoreGraphics retained text must cache attributed strings, not separate attributes dictionaries")
    if "@property(nonatomic, strong) NSAttributedString* attributedText" not in text:
        fail("CoreGraphics retained text must store cached attributed strings")
    if 'NSDictionary<NSString*, id>* resource = self.orenTextResources[@(textID)]' in text:
        fail("CoreGraphics retained text draws must not use dictionary casts")
    if "CFMutableDictionaryRef _orenTextAttributes" not in text:
        fail("CoreGraphics text draws must cache UIKit text attributes in a scalar-key CF dictionary")
    if "OrenAVMGfxTextAttributesForRGBA" not in text:
        fail("CoreGraphics text draws must use the per-view text attribute cache")
    attr_helper_start = resource_text.rfind("NSDictionary<NSAttributedStringKey, id>* OrenAVMGfxTextAttributesForRGBA")
    attr_helper_end = resource_text.find("BOOL OrenAVMGfxPutTextResource", attr_helper_start)
    if attr_helper_start < 0 or attr_helper_end < 0:
        fail("missing CoreGraphics text attribute helper body")
    attr_helper = resource_text[attr_helper_start:attr_helper_end]
    mru_pos = attr_helper.find("lastRGBA && lastAttributes && *lastAttributes && *lastRGBA == rgbaValue")
    scalar_key_pos = attr_helper.find("const void* key = OrenAVMGfxTextAttributeKey(rgbaValue)")
    if mru_pos < 0 or scalar_key_pos < 0 or mru_pos > scalar_key_pos:
        fail("CoreGraphics text attribute cache must check the scalar MRU before scalar-map lookup")
    if "NSNumber* key = @(rgbaValue)" in attr_helper or "NSMutableDictionary<NSNumber*, NSDictionary<NSAttributedStringKey, id>*>* orenTextAttributes" in text:
        fail("CoreGraphics text attribute cache must not box RGBA keys")
    if "CFDictionaryGetValue(*attrsByRGBA, key)" not in attr_helper or "CFDictionarySetValue(*attrsByRGBA, key" not in attr_helper:
        fail("CoreGraphics text attribute cache must use scalar-key CF dictionary lookup/storage")
    if "OrenAVMGfxTextAttributes(OrenAVMGfxRGBAValue(payload + 8))" in text:
        fail("CoreGraphics immediate text draws must not rebuild text attributes per draw")
    if "OrenAVMGfxTextAttributes(OrenAVMGfxRGBAValue(payload + 4))" in text:
        fail("CoreGraphics retained text resources must use cached text attributes")
    if "@interface OrenAVMGfxImageResource" not in text:
        fail("CoreGraphics retained images must use typed resource objects")
    if "NSMutableDictionary<NSNumber*, UIImage*>* orenImages" in text:
        fail("CoreGraphics retained images must not store bare UIImage values")
    if "NSMutableDictionary<NSNumber*, OrenAVMGfxImageResource*>* orenImages" in text:
        fail("CoreGraphics retained image lookups must avoid boxed NSNumber image IDs")
    if "CFMutableDictionaryRef _orenImagesByID" not in text:
        fail("CoreGraphics retained images must use a scalar-key CF dictionary")
    if "OrenAVMGfxHandleImageCommand(ctx," not in frame_command_text:
        fail("CoreGraphics frame traversal must delegate retained image opcodes to OrenAVMGraphicsResources")
    if "OrenAVMGfxRetainedImageResource(images ? *images : NULL, imageID)" not in resource_text:
        fail("CoreGraphics retained image draw paths must use the typed scalar-map resource helper")
    if "@(imageID)" in text:
        fail("CoreGraphics retained image draw/upload paths must not box image IDs")
    if "orenImagePixels" in text:
        fail("CoreGraphics retained image pixel accounting must not use a parallel dictionary")
    if "NSData* imageData = [NSData dataWithBytes:rgba" in text or "CGDataProviderCreateWithCFData" in text:
        fail("CoreGraphics retained image uploads must use provider-owned raw bytes, not NSData wrappers")
    if "CGDataProviderCreateWithData(NULL, imageBytes" not in text or "OrenAVMGfxReleaseImageBytes" not in text:
        fail("CoreGraphics retained image uploads must transfer raw bytes to the CG provider release callback")
    image_rgba_start = resource_source_text.find("UIImage* OrenAVMGfxImageRGBA")
    image_rgba_end = resource_source_text.find("BOOL OrenAVMGfxPutImageResource", image_rgba_start)
    if image_rgba_start < 0 or image_rgba_end < 0:
        fail("missing CoreGraphics retained image factory")
    image_rgba_body = resource_source_text[image_rgba_start:image_rgba_end]
    require_before(image_rgba_body,
                   "if (!colorSpace) {\n        CGDataProviderRelease(provider);\n        return nil;\n    }",
                   "CGImageRef image = CGImageCreate",
                   "CoreGraphics retained image factory must release provider on color-space allocation failure")
    put_image_start = resource_source_text.find("BOOL OrenAVMGfxPutImageResource")
    put_image_end = resource_source_text.find("void OrenAVMGfxRemoveImageResource", put_image_start)
    if put_image_start < 0 or put_image_end < 0:
        fail("missing CoreGraphics retained image upload helper")
    put_image_body = resource_source_text[put_image_start:put_image_end]
    image_map_alloc = put_image_body.find("CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks)")
    image_create = put_image_body.find("OrenAVMGfxImageRGBA(rgba, width, height, byteCount)")
    if image_map_alloc < 0 or image_create < 0:
        fail("CoreGraphics retained image upload helper missing scalar map or image creation path")
    if image_map_alloc > image_create:
        fail("CoreGraphics retained image uploads must preflight scalar-map storage before CoreGraphics image creation")
    require_before(put_image_body,
                   "if (!resource) return NO;",
                   "CFDictionarySetValue(*imagesByID",
                   "CoreGraphics retained image uploads must guard resource allocation before map insertion")
    if "UIImage* image = OrenAVMGfxImageRGBA(payload + 16" in resource_text:
        fail("CoreGraphics retained image command path must let the upload helper create images after preflight")
    if "OrenAVMGfxSubrectInImage" not in text:
        fail("CoreGraphics retained image sub-rect checks must use the overflow-safe helper")
    if "return sw > 0 && sh > 0 &&" not in text:
        fail("CoreGraphics retained image sub-rect checks must reject zero source dimensions locally")
    if "OrenAVMGfxDrawImageSubrect" not in text:
        fail("CoreGraphics retained image sub-rect draws must share the checked draw helper")
    if "if (!cgImage || w == 0 || h == 0 || !OrenAVMGfxSubrectInImage" not in text:
        fail("CoreGraphics retained image sub-rect draws must reject zero destination dimensions locally")
    if "OrenAVMGfxImageRectsHaveZeroSize" not in text:
        fail("CoreGraphics batched retained image sub-rect draws must preflight zero-size rects before resource lookup")
    if "OrenAVMGfxSubrectInImage(sx, sy, sw, sh, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage))" in text:
        fail("CoreGraphics batched image sub-rect draws must cache CGImage dimensions")
    if "size_t imageWidth = CGImageGetWidth(cgImage)" not in text or "size_t imageHeight = CGImageGetHeight(cgImage)" not in text:
        fail("CoreGraphics batched image sub-rect draws must cache image dimensions")
    image_command_start = resource_source_text.find("BOOL OrenAVMGfxHandleImageCommand")
    image_command_end = resource_source_text.find("const void* OrenAVMGfxRetainedTextKey", image_command_start)
    if image_command_start < 0 or image_command_end < 0:
        fail("missing CoreGraphics retained image command helper body")
    image_command = resource_source_text[image_command_start:image_command_end]
    single_image_start = image_command.find("case 65:")
    single_image_end = image_command.find("case 66:", single_image_start)
    subrect_image_start = image_command.find("case 67:")
    subrect_image_end = image_command.find("case 71:", subrect_image_start)
    batched_image_start = image_command.find("case 71:")
    batched_image_end = image_command.find("default:", batched_image_start)
    if single_image_start < 0 or single_image_end < 0 or subrect_image_start < 0 or subrect_image_end < 0 or batched_image_start < 0 or batched_image_end < 0:
        fail("missing CoreGraphics retained image preflight paths")
    require_before(
        image_command[single_image_start:single_image_end],
        "if (w == 0 || h == 0) return YES;",
        "OrenAVMGfxRetainedImageResource(images ? *images : NULL, imageID)",
        "CoreGraphics retained image draws must reject zero destinations before retained image lookup",
    )
    require_before(
        image_command[subrect_image_start:subrect_image_end],
        "if (sw == 0 || sh == 0 || w == 0 || h == 0) return YES;",
        "OrenAVMGfxRetainedImageResource(images ? *images : NULL, imageID)",
        "CoreGraphics retained image subrect draws must reject zero dimensions before retained image lookup",
    )
    require_before(
        image_command[batched_image_start:batched_image_end],
        "rectCount == ((uint32_t)payloadLen - 8u) / 32u",
        "OrenAVMGfxRetainedImageResource(images ? *images : NULL, imageID)",
        "CoreGraphics batched retained image draws must validate rect counts before retained image lookup",
    )
    require_before(
        image_command[batched_image_start:batched_image_end],
        "if (OrenAVMGfxImageRectsHaveZeroSize(payload + 8, rectCount)) return YES;",
        "OrenAVMGfxRetainedImageResource(images ? *images : NULL, imageID)",
        "CoreGraphics batched retained image draws must reject zero-size rects before retained image lookup",
    )
    if "@interface OrenAVMGfxModelResource" not in text:
        fail("CoreGraphics retained models must use typed resource objects")
    if 'NSMutableDictionary<NSNumber*, NSDictionary<NSString*, NSNumber*>*>* orenModels3D' in text:
        fail("CoreGraphics retained models must not use dictionary payload records")
    if 'NSMutableDictionary<NSNumber*, OrenAVMGfxModelResource*>* orenModels3D' in text:
        fail("CoreGraphics retained model lookups must avoid boxed NSNumber model IDs")
    if "CFMutableDictionaryRef _orenModels3DByID" not in text:
        fail("CoreGraphics retained models must use a scalar-key CF dictionary")
    if "OrenAVMGfxRetainedModelResource(models, meshID)" not in resource_text:
        fail("CoreGraphics retained model draws must use the typed scalar-map resource helper")
    if "OrenAVMGfxPutModelResource(models," not in resource_text:
        fail("CoreGraphics retained model uploads must live in OrenAVMGraphicsResources")
    if "OrenAVMGfxRemoveModelResource(models ? *models : NULL" not in resource_text:
        fail("CoreGraphics retained model removals must live in OrenAVMGraphicsResources")
    put_model_start = resource_source_text.find("BOOL OrenAVMGfxPutModelResource")
    put_model_end = resource_source_text.find("void OrenAVMGfxRemoveModelResource", put_model_start)
    if put_model_start < 0 or put_model_end < 0:
        fail("missing CoreGraphics retained model upload helper")
    put_model_body = resource_source_text[put_model_start:put_model_end]
    require_before(put_model_body,
                   "OrenAVMGfxEnsureRetainedResourceMap(models)",
                   "[[OrenAVMGfxModelResource alloc] init]",
                   "CoreGraphics retained model uploads must preflight scalar-map storage before resource allocation")
    require_before(put_model_body,
                   "if (!model) return NO;",
                   "CFDictionarySetValue(*models",
                   "CoreGraphics retained model uploads must guard resource allocation before map insertion")
    if "CFDictionarySetValue(_orenModels3DByID" in view_text or "CFDictionaryRemoveValue(_orenModels3DByID" in view_text:
        fail("CoreGraphics view must not mutate retained model maps directly")
    if 'model[@"mesh_id"]' in text or '@"scale_milli"' in text:
        fail("CoreGraphics retained model draws must not use string-key dictionary lookups")
    retained3d_draw_start = resource_source_text.find("void OrenAVMGfxDrawMesh3DResource(CGContextRef ctx,")
    retained3d_draw_end = resource_source_text.find("BOOL OrenAVMGfxHandleMeshCommand(CGContextRef ctx,", retained3d_draw_start)
    if retained3d_draw_start < 0 or retained3d_draw_end < 0:
        fail("missing CoreGraphics retained 3D draw helper block")
    retained3d_draw_body = resource_source_text[retained3d_draw_start:retained3d_draw_end]
    if "if (!ctx || !payload || opacity <= 0.0) return;" not in retained3d_draw_body:
        fail("CoreGraphics retained 3D mesh/model draws must skip fully transparent work before retained lookup and ordering")
    for forbidden in (
        "OrenAVMGfxTriangleOrder inlineOrder[OrenAVMGfxInlineTriangleOrderCapacity]",
        "OrenAVMGfxSortTriangleOrder(order, visibleCount)",
        "const uint8_t* tri = idx + ((size_t)order[oi].triangle * 12u)",
        "const uint8_t* tri = tris + ((size_t)order[oi].triangle * meshStride)",
        "OrenAVMGfxRetainedMaterialRGBA(_orenMaterials3DByID",
        "OrenAVMGfxRetainedModelResource(_orenModels3DByID",
    ):
        if forbidden in frame_command_text:
            fail("CoreGraphics frame traversal must not expand retained 3D mesh payloads directly")
    if "static BOOL OrenAVMGfxTriangleIsDegenerate" not in resource_text:
        fail("CoreGraphics retained mesh painter must have a local degenerate-triangle predicate")
    if resource_text.count("if (OrenAVMGfxTriangleIsDegenerate(x1, y1, x2, y2, x3, y3)) continue;") < 3:
        fail("CoreGraphics retained 2D and 3D mesh painters must skip degenerate triangle fills")
    geometry_text = GEOMETRY_SOURCE.read_text()
    if "static BOOL OrenAVMGfxGeometryTriangleIsDegenerate" not in geometry_text:
        fail("CoreGraphics immediate painter must have a local degenerate-triangle predicate")
    if geometry_text.count("OrenAVMGfxGeometryTriangleIsDegenerate") < 3:
        fail("CoreGraphics immediate triangle paths must skip degenerate triangle fills")
    for token in (
        "if (w == 0 || h == 0) return YES;",
        "if (radius == 0) return YES;",
    ):
        if token not in geometry_text:
            fail(f"CoreGraphics immediate primitive painter must skip zero-size shape work: {token}")
    print("OK: CoreGraphics retained resources use compact typed records")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
