#!/usr/bin/env python3
"""Verify CoreGraphics immediate primitive drawing stays in the geometry helper."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
VIEW_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsView.m"
FRAME_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsFrame.m"
GEOMETRY_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsGeometry.h"
GEOMETRY_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsGeometry.m"
BUILD_SCRIPT = ROOT / "scripts/build_libavm_ios.sh"
COMPILE_SMOKE = ROOT / "scripts/verify_libavm_ios_compile_smokes.sh"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    view_text = VIEW_SOURCE.read_text()
    frame_text = FRAME_SOURCE.read_text()
    geometry_text = GEOMETRY_HEADER.read_text() + "\n" + GEOMETRY_SOURCE.read_text()
    build_text = BUILD_SCRIPT.read_text()
    smoke_text = COMPILE_SMOKE.read_text()

    if '"OrenAVMGraphicsGeometry.h"' not in frame_text:
        fail("CoreGraphics frame traversal must import OrenAVMGraphicsGeometry")
    if "sdk/ios/OrenAVMKit/OrenAVMGraphicsGeometry.m" not in build_text:
        fail("iOS build must compile OrenAVMGraphicsGeometry.m")
    if "sdk/ios/OrenAVMKit/OrenAVMGraphicsGeometry.m" not in smoke_text:
        fail("iOS compile smoke must compile OrenAVMGraphicsGeometry.m")
    if "OrenAVMGfxDrawImmediatePrimitive(CGContextRef ctx," not in geometry_text:
        fail("CoreGraphics primitive draw helper must live in OrenAVMGraphicsGeometry")
    if "OrenAVMGfxDrawImmediatePrimitive(ctx, opcode, payload, payloadLen)" not in frame_text:
        fail("CoreGraphics frame traversal must delegate primitive drawing to OrenAVMGraphicsGeometry")

    forbidden_view_tokens = (
        "OrenAVMGfxSetFillColorBytes",
        "OrenAVMGfxSetStrokeColorBytes",
        "CGContextStrokeRectWithWidth(ctx,",
        "UIBezierPath* path = [UIBezierPath bezierPathWithRoundedRect",
        "CGContextFillEllipseInRect(ctx, oval)",
        "CGContextStrokeEllipseInRect(ctx, oval)",
        "CGContextAddLineToPoint(ctx, (CGFloat)x2",
        "const uint8_t* tris = payload + 8",
        "OrenAVMGfxDrawImmediatePrimitive(ctx, opcode, payload, payloadLen)",
    )
    for token in forbidden_view_tokens:
        if token in view_text:
            fail(f"CoreGraphics primitive payload expansion must not live in the view: {token}")

    required_geometry_tokens = (
        "case 1:",
        "case 3:",
        "case 4:",
        "case 5:",
        "case 6:",
        "case 7:",
        "case 8:",
        "case 9:",
        "case 10:",
        "CGContextStrokeRectWithWidth(ctx,",
        "UIBezierPath* path = [UIBezierPath bezierPathWithRoundedRect",
        "CGContextFillEllipseInRect(ctx, oval)",
        "CGContextStrokePath(ctx)",
        "CGContextFillPath(ctx)",
    )
    for token in required_geometry_tokens:
        if token not in geometry_text:
            fail(f"CoreGraphics primitive helper is missing expected draw logic: {token}")

    print("OK: CoreGraphics primitive drawing lives in OrenAVMGraphicsGeometry")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
