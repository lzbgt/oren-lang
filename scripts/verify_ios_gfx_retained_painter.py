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
    if 'NSMutableDictionary<NSNumber*, NSDictionary<NSString*, id>*>* orenMeshes' in text:
        fail("CoreGraphics retained meshes must not use dictionary payload records")
    if "NSMutableDictionary<NSNumber*, UIColor*>* orenMaterials3D" in text:
        fail("CoreGraphics retained materials must store scalar RGBA values")
    if '@"color": OrenAVMGfxColor' in text:
        fail("CoreGraphics retained mesh colors must stay scalar, not retained UIColor objects")
    print("OK: CoreGraphics retained 3D painter uses compact order buffers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
