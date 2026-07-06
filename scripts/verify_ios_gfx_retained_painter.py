#!/usr/bin/env python3
"""Verify retained 3D fallback painter ordering stays on compact buffers."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsView.m"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    text = SOURCE.read_text()
    required = [
        "OrenAVMGfxTriangleOrder",
        "OrenAVMGfxTriangleOrderBuffer",
        "OrenAVMGfxSortTriangleOrder",
    ]
    for token in required:
        if token not in text:
            fail(f"missing retained 3D painter helper: {token}")
    if "NSMutableSet<NSNumber*>* drawn" in text or "[drawn containsObject:" in text:
        fail("retained 3D painter path still uses boxed set tracking")
    if text.count("OrenAVMGfxSortTriangleOrder(order, visibleCount)") < 2:
        fail("expected sorted order path for indexed and packed retained 3D meshes")
    if "@interface OrenAVMGfxMeshResource" not in text:
        fail("CoreGraphics retained meshes must use typed resource objects")
    if "static UIColor* OrenAVMGfxColor(const uint8_t* rgba)" in text:
        fail("CoreGraphics immediate primitive colors must not allocate UIColor wrappers")
    if "CGContextSetFillColorWithColor(ctx, color.CGColor)" in text or "CGContextSetStrokeColorWithColor(ctx, color.CGColor)" in text:
        fail("CoreGraphics immediate primitive colors must use direct byte/scalar setters")
    if "OrenAVMGfxSetFillColorBytes(ctx, payload + 16)" not in text or "OrenAVMGfxSetStrokeColorBytes(ctx, payload + 20)" not in text:
        fail("CoreGraphics immediate primitive color fast path is missing")
    if 'NSMutableDictionary<NSNumber*, NSDictionary<NSString*, id>*>* orenMeshes' in text:
        fail("CoreGraphics retained meshes must not use dictionary payload records")
    if "NSMutableDictionary<NSNumber*, UIColor*>* orenMaterials3D" in text:
        fail("CoreGraphics retained materials must store scalar RGBA values")
    if '@"color": OrenAVMGfxColor' in text:
        fail("CoreGraphics retained mesh colors must stay scalar, not retained UIColor objects")
    if "@interface OrenAVMGfxTextResource" not in text:
        fail("CoreGraphics retained text must use typed resource objects")
    if 'NSMutableDictionary<NSNumber*, NSDictionary<NSString*, id>*>* orenTextResources' in text:
        fail("CoreGraphics retained text must not use dictionary payload records")
    if 'self.orenTextResources[@(textID)] = @{@"text": text, @"color": color}' in text:
        fail("CoreGraphics retained text must cache typed text attributes")
    if 'NSDictionary<NSString*, id>* resource = self.orenTextResources[@(textID)]' in text:
        fail("CoreGraphics retained text draws must not use dictionary casts")
    if "@interface OrenAVMGfxImageResource" not in text:
        fail("CoreGraphics retained images must use typed resource objects")
    if "NSMutableDictionary<NSNumber*, UIImage*>* orenImages" in text:
        fail("CoreGraphics retained images must not store bare UIImage values")
    if "orenImagePixels" in text:
        fail("CoreGraphics retained image pixel accounting must not use a parallel dictionary")
    if "OrenAVMGfxSubrectInImage" not in text:
        fail("CoreGraphics retained image sub-rect checks must use the overflow-safe helper")
    if "@interface OrenAVMGfxModelResource" not in text:
        fail("CoreGraphics retained models must use typed resource objects")
    if 'NSMutableDictionary<NSNumber*, NSDictionary<NSString*, NSNumber*>*>* orenModels3D' in text:
        fail("CoreGraphics retained models must not use dictionary payload records")
    if 'model[@"mesh_id"]' in text or '@"scale_milli"' in text:
        fail("CoreGraphics retained model draws must not use string-key dictionary lookups")
    print("OK: CoreGraphics retained resources use compact typed records")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
