#!/usr/bin/env python3
"""Verify iOS GFX input event helpers stay allocation-bounded."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
INPUT_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGFXInput.m"
SDK_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMKit.m"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    input_text = INPUT_SOURCE.read_text()
    sdk_text = SDK_SOURCE.read_text()

    if "orenPutGraphicsInputEventBytes:(const void*)bytes" not in sdk_text:
        fail("missing internal raw-byte GFX input enqueue helper")
    if "avm_embed_gfx_input_put(_handle, (const uint8_t*)bytes, length, &result)" not in sdk_text:
        fail("raw-byte GFX input helper must call the C queue API directly")
    if "return [self orenPutGraphicsInputEventBytes:data.bytes length:data.length error:error];" not in sdk_text:
        fail("public NSData GFX input API must delegate to the raw-byte helper")

    if "static NSData* OrenAVMGFXInputMakeEvent" in input_text:
        fail("typed GFX input helpers must not allocate NSData events")
    if "[self putGraphicsInputEventData:" in input_text:
        fail("typed GFX input helpers must enqueue raw bytes directly")
    if "NSMutableData* payload" in input_text:
        fail("text/composition GFX input helpers must not allocate separate payload buffers")
    if "OrenAVMGFXInputPutEventParts" not in input_text or "uint8_t stackEvent[stackCap]" not in input_text:
        fail("missing stack-first GFX input event construction helper")
    if "NSMutableData* event = [NSMutableData dataWithLength:totalLen]" not in input_text:
        fail("large variable GFX input events need exactly one event buffer fallback")
    if input_text.count("OrenAVMGFXInputPutEvent(self,") < 7:
        fail("fixed-size GFX input helpers must use the stack-backed event helper")
    if input_text.count("OrenAVMGFXInputPutEventParts(self,") != 2:
        fail("text and composition events must use segmented event construction")
    if "dataWithLength:4u + utf8.length" in input_text or "dataWithLength:12u + utf8.length" in input_text:
        fail("text/composition GFX input helpers regressed to payload allocation")

    print("OK: iOS GFX input events use stack-first byte enqueue")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
