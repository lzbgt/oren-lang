#!/usr/bin/env python3
"""Verify CoreGraphics frame traversal/state helpers stay out of the view."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
VIEW_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsView.m"
FRAME_HEADER = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsFrame.h"
FRAME_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsFrame.m"
BUILD_SCRIPT = ROOT / "scripts/build_libavm_ios.sh"
COMPILE_SMOKE = ROOT / "scripts/verify_libavm_ios_compile_smokes.sh"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    view_text = VIEW_SOURCE.read_text()
    frame_text = FRAME_HEADER.read_text() + "\n" + FRAME_SOURCE.read_text()
    build_text = BUILD_SCRIPT.read_text()
    smoke_text = COMPILE_SMOKE.read_text()

    if '"OrenAVMGraphicsFrame.h"' not in view_text:
        fail("CoreGraphics view must import OrenAVMGraphicsFrame")
    if "sdk/ios/OrenAVMKit/OrenAVMGraphicsFrame.m" not in build_text:
        fail("iOS build must compile OrenAVMGraphicsFrame.m")
    if "sdk/ios/OrenAVMKit/OrenAVMGraphicsFrame.m" not in smoke_text:
        fail("iOS compile smoke must compile OrenAVMGraphicsFrame.m")

    for token in (
        "BOOL OrenAVMGfxFrameDataIsValid(NSData* frame)",
        "void OrenAVMGfxFrameStateInit(OrenAVMGfxFrameState* state)",
        "BOOL OrenAVMGfxHandleFrameStateCommand(CGContextRef ctx,",
        "void OrenAVMGfxRestoreFrameState(CGContextRef ctx, OrenAVMGfxFrameState* state)",
        "typedef struct {",
        "CFMutableDictionaryRef* textResources",
        "void OrenAVMGfxDrawFrame(CGContextRef ctx, NSData* frame, OrenAVMGfxFrameDrawContext* context)",
        "CGFloat opacityStack[64]",
        "BOOL depthEnabledStack[64]",
    ):
        if token not in frame_text:
            fail(f"CoreGraphics frame helper is missing expected state logic: {token}")

    if "OrenAVMGfxFrameDrawContext context = {" not in view_text or "OrenAVMGfxDrawFrame(ctx, frame, &context)" not in view_text:
        fail("CoreGraphics drawRect must delegate OGF0 traversal to OrenAVMGraphicsFrame")
    if "OrenAVMGfxHandleFrameStateCommand(ctx, opcode, payload, payloadLen, &frameState)" not in frame_text:
        fail("CoreGraphics frame traversal must delegate state opcodes to OrenAVMGfxHandleFrameStateCommand")
    if "OrenAVMGfxRestoreFrameState(ctx, &frameState)" not in frame_text:
        fail("CoreGraphics frame traversal must delegate final state cleanup to OrenAVMGraphicsFrame")
    if "frameState.depthEnabled" not in frame_text or "frameState.nearZ" not in frame_text or "frameState.farZ" not in frame_text:
        fail("CoreGraphics retained 3D draws must consume frame-state depth windows")

    forbidden_view_tokens = (
        "uint8_t opcode =",
        "uint16_t payloadLen =",
        "OrenAVMGfxDrawImmediatePrimitive(ctx, opcode",
        "OrenAVMGfxHandleFrameStateCommand(ctx, opcode",
        "OrenAVMGfxRestoreFrameState(ctx, &frameState)",
        "uint32_t clipDepth =",
        "CGFloat opacityStack[64]",
        "BOOL depthEnabledStack[64]",
        "CGContextClipToRect(ctx,",
        "CGContextTranslateCTM(ctx,",
        "CGContextSetAlpha(ctx,",
        "while (stateDepth > 0)",
    )
    for token in forbidden_view_tokens:
        if token in view_text:
            fail(f"CoreGraphics frame state logic must not live in the view: {token}")

    print("OK: CoreGraphics frame state helpers live in OrenAVMGraphicsFrame")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
