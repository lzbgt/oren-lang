#!/usr/bin/env python3
"""Verify CoreGraphics retained resource helpers stay out of the view."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
VIEW_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsView.m"
FRAME_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsFrame.m"
RESOURCE_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsResources.h"
RESOURCE_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsResources.m"
BUILD_SCRIPT = ROOT / "scripts/build_libavm_ios.sh"
COMPILE_SMOKE = ROOT / "scripts/verify_libavm_ios_compile_smokes.sh"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    view_text = VIEW_SOURCE.read_text()
    frame_text = FRAME_SOURCE.read_text()
    resource_text = RESOURCE_HEADER.read_text() + "\n" + RESOURCE_SOURCE.read_text()
    build_text = BUILD_SCRIPT.read_text()
    smoke_text = COMPILE_SMOKE.read_text()

    if '"OrenAVMGraphicsResources.h"' not in frame_text:
        fail("CoreGraphics frame traversal must import OrenAVMGraphicsResources")
    if "sdk/ios/OrenAVMKit/OrenAVMGraphicsResources.m" not in build_text:
        fail("iOS build must compile OrenAVMGraphicsResources.m")
    if "sdk/ios/OrenAVMKit/OrenAVMGraphicsResources.m" not in smoke_text:
        fail("iOS compile smoke must compile OrenAVMGraphicsResources.m")
    for token in (
        "@interface OrenAVMGfxMeshResource",
        "@interface OrenAVMGfxTextResource",
        "@interface OrenAVMGfxImageResource",
        "@interface OrenAVMGfxModelResource",
        "OrenAVMGfxRetainedImageKey",
        "OrenAVMGfxImageRGBA",
        "OrenAVMGfxPutImageResource",
        "OrenAVMGfxRemoveImageResource",
        "OrenAVMGfxDrawImageSubrect",
        "OrenAVMGfxRetainedTextKey",
        "OrenAVMGfxTextAttributesForRGBA",
        "OrenAVMGfxDrawTextBytes",
        "OrenAVMGfxPutTextResource",
        "OrenAVMGfxDrawTextResourcePositions",
        "OrenAVMGfxRemoveTextResource",
        "OrenAVMGfxRetainedMeshKey",
        "OrenAVMGfxPutTriangleMeshResource",
        "OrenAVMGfxPutIndexedMeshResource",
        "OrenAVMGfxRemoveMeshResource",
        "OrenAVMGfxDrawMesh2DResource",
        "OrenAVMGfxDrawMesh3DResource",
        "OrenAVMGfxRetainedMaterialKey",
        "OrenAVMGfxRetainedMaterialRGBA",
        "OrenAVMGfxPutMaterialResource",
        "OrenAVMGfxRemoveMaterialResource",
        "OrenAVMGfxRetainedModelKey",
        "OrenAVMGfxPutModelResource",
        "OrenAVMGfxRemoveModelResource",
        "OrenAVMGfxCopyPayloadBytes",
        "OrenAVMGfxTriangleOrderAppend",
        "OrenAVMGfxSortTriangleOrder",
        "OrenAVMGfxMesh3DIndexedZSumModel",
        "OrenAVMGfxMesh3DModelCoord",
    ):
        if token not in resource_text:
            fail(f"CoreGraphics resource helper must live in OrenAVMGraphicsResources: {token}")
    for forbidden in (
        "@interface OrenAVMGfxMeshResource",
        "@implementation OrenAVMGfxMeshResource",
        "static OrenAVMGfxTriangleOrder* OrenAVMGfxTriangleOrderBuffer",
        "static const void* OrenAVMGfxRetainedImageKey",
        "static OrenAVMGfxImageResource* OrenAVMGfxRetainedImageResource",
        "static UIImage* OrenAVMGfxImageRGBA",
        "- (void)orenPutImage:",
        "- (void)orenRemoveImageWithID:",
        "static void OrenAVMGfxDrawImageSubrect",
        "static const void* OrenAVMGfxRetainedTextKey",
        "static OrenAVMGfxTextResource* OrenAVMGfxRetainedTextResource",
        "static NSDictionary<NSAttributedStringKey, id>* OrenAVMGfxTextAttributes",
        "static NSDictionary<NSAttributedStringKey, id>* OrenAVMGfxTextAttributesForView",
        "CFDictionarySetValue(_orenTextResourcesByID",
        "CFDictionaryRemoveValue(_orenTextResourcesByID",
        "CFDictionarySetValue(_orenMeshesByID",
        "CFDictionaryRemoveValue(_orenMeshesByID",
        "CFDictionarySetValue(_orenMaterials3DByID",
        "CFDictionaryRemoveValue(_orenMaterials3DByID",
        "CFDictionarySetValue(_orenModels3DByID",
        "CFDictionaryRemoveValue(_orenModels3DByID",
        "static const void* OrenAVMGfxRetainedMeshKey",
        "static OrenAVMGfxMeshResource* OrenAVMGfxRetainedMeshResource",
        "static const void* OrenAVMGfxRetainedMaterialKey",
        "static BOOL OrenAVMGfxRetainedMaterialRGBA",
        "static const void* OrenAVMGfxRetainedModelKey",
        "static OrenAVMGfxModelResource* OrenAVMGfxRetainedModelResource",
        "OrenAVMGfxPutImageResource(",
        "OrenAVMGfxRemoveImageResource(",
        "OrenAVMGfxPutTextResource(",
        "OrenAVMGfxDrawTextResourcePositions(",
        "OrenAVMGfxRemoveTextResource(",
        "OrenAVMGfxPutTriangleMeshResource(",
        "OrenAVMGfxPutIndexedMeshResource(",
        "OrenAVMGfxRemoveMeshResource(",
        "OrenAVMGfxDrawMesh2DResource(",
        "OrenAVMGfxDrawMesh3DResource(",
        "OrenAVMGfxPutMaterialResource(",
        "OrenAVMGfxPutModelResource(",
    ):
        if forbidden in view_text:
            fail(f"CoreGraphics view must not define retained resource helper: {forbidden}")
    for token in (
        "BOOL OrenAVMGfxHandleImageCommand(CGContextRef ctx,",
        "BOOL OrenAVMGfxHandleTextCommand(CGContextRef ctx,",
        "BOOL OrenAVMGfxHandleMeshCommand(CGContextRef ctx,",
        "case 64:",
        "case 68:",
        "case 80:",
        "case 95:",
    ):
        if token not in resource_text:
            fail(f"CoreGraphics resource command helper is missing expected routing: {token}")
    for token in (
        "OrenAVMGfxHandleMeshCommand(ctx,",
        "context->materials3D",
        "frameState.depthEnabled",
        "OrenAVMGfxHandleTextCommand(ctx,",
        "context->lastTextAttributes",
        "OrenAVMGfxHandleImageCommand(ctx,",
        "context->retainedImagePixelCount",
    ):
        if token not in frame_text:
            fail(f"CoreGraphics frame traversal must delegate retained resource opcodes: {token}")
    for forbidden in (
        "OrenAVMGfxPutImageResource(context->images,",
        "OrenAVMGfxRemoveImageResource(context->images ? *context->images : NULL",
        "OrenAVMGfxPutTextResource(context->textResources,",
        "OrenAVMGfxDrawTextResourcePositions(context->textResources ? *context->textResources : NULL",
        "OrenAVMGfxRemoveTextResource(context->textResources ? *context->textResources : NULL",
        "OrenAVMGfxPutTriangleMeshResource(context->meshes,",
        "OrenAVMGfxPutIndexedMeshResource(context->meshes,",
        "OrenAVMGfxRemoveMeshResource(context->meshes ? *context->meshes : NULL",
        "OrenAVMGfxDrawMesh2DResource(ctx, context->meshes ? *context->meshes : NULL",
        "OrenAVMGfxDrawMesh3DResource(ctx,",
        "OrenAVMGfxPutMaterialResource(context->materials3D,",
        "OrenAVMGfxPutModelResource(context->models3D,",
    ):
        if forbidden in frame_text:
            fail(f"CoreGraphics frame traversal must not own retained resource payloads: {forbidden}")

    print("OK: CoreGraphics retained resource helpers live in OrenAVMGraphicsResources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
