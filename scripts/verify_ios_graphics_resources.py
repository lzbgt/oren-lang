#!/usr/bin/env python3
"""Verify CoreGraphics retained resource helpers stay out of the view."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
VIEW_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsView.m"
RESOURCE_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsResources.h"
RESOURCE_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsResources.m"
BUILD_SCRIPT = ROOT / "scripts/build_libavm_ios.sh"
COMPILE_SMOKE = ROOT / "scripts/verify_libavm_ios_compile_smokes.sh"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    view_text = VIEW_SOURCE.read_text()
    resource_text = RESOURCE_HEADER.read_text() + "\n" + RESOURCE_SOURCE.read_text()
    build_text = BUILD_SCRIPT.read_text()
    smoke_text = COMPILE_SMOKE.read_text()

    if '"OrenAVMGraphicsResources.h"' not in view_text:
        fail("CoreGraphics view must import OrenAVMGraphicsResources")
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
        "OrenAVMGfxRetainedMeshKey",
        "OrenAVMGfxRetainedMaterialKey",
        "OrenAVMGfxRetainedMaterialRGBA",
        "OrenAVMGfxRetainedModelKey",
        "OrenAVMGfxCopyPayloadBytes",
        "OrenAVMGfxTriangleOrderBuffer",
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
        "static const void* OrenAVMGfxRetainedMeshKey",
        "static OrenAVMGfxMeshResource* OrenAVMGfxRetainedMeshResource",
        "static const void* OrenAVMGfxRetainedMaterialKey",
        "static BOOL OrenAVMGfxRetainedMaterialRGBA",
        "static const void* OrenAVMGfxRetainedModelKey",
        "static OrenAVMGfxModelResource* OrenAVMGfxRetainedModelResource",
    ):
        if forbidden in view_text:
            fail(f"CoreGraphics view must not define retained resource helper: {forbidden}")
    if "OrenAVMGfxPutImageResource(&_orenImagesByID," not in view_text:
        fail("CoreGraphics retained image uploads must delegate map mutation to OrenAVMGraphicsResources")
    if "OrenAVMGfxRemoveImageResource(_orenImagesByID, imageID, &_retainedImagePixelCount)" not in view_text:
        fail("CoreGraphics retained image removals must delegate pixel accounting to OrenAVMGraphicsResources")

    print("OK: CoreGraphics retained resource helpers live in OrenAVMGraphicsResources")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
