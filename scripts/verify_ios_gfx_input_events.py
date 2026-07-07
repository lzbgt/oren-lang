#!/usr/bin/env python3
"""Verify iOS GFX input event helpers stay allocation-bounded."""

from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
INPUT_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGFXInput.m"
SDK_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMKit.m"
GRAPHICS_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMGraphicsView.m"
METAL_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMMetalView.m"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    input_text = INPUT_SOURCE.read_text()
    sdk_text = SDK_SOURCE.read_text()
    graphics_text = GRAPHICS_SOURCE.read_text()
    metal_text = METAL_SOURCE.read_text()
    renderer_text = graphics_text + "\n" + metal_text

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
    if "dataUsingEncoding:NSUTF8StringEncoding" in input_text:
        fail("text/composition GFX input helpers must encode UTF-8 directly into event buffers")
    if "OrenAVMGFXInputPutEventParts" not in input_text or "uint8_t stackEvent[stackCap]" not in input_text:
        fail("missing stack-first GFX input event construction helper")
    if "OrenAVMGFXInputPutUTF8EventParts" not in input_text or "OrenAVMGFXInputWriteUTF8" not in input_text:
        fail("missing direct UTF-8 GFX input event helper")
    if "NSMutableData* event" in input_text or "[NSMutableData dataWithLength:totalLen]" in input_text:
        fail("large variable GFX input events must use raw heap buffers, not NSMutableData wrappers")
    if input_text.count("uint8_t* event = (uint8_t*)malloc(totalLen)") != 2 or input_text.count("free(event)") < 3:
        fail("large variable GFX input events need raw heap fallbacks with explicit cleanup")
    if input_text.count("OrenAVMGFXInputPutEvent(self,") < 7:
        fail("fixed-size GFX input helpers must use the stack-backed event helper")
    if input_text.count("OrenAVMGFXInputPutUTF8EventParts(self,") != 2:
        fail("text and composition events must encode directly through segmented UTF-8 event construction")
    if "dataWithLength:4u + utf8.length" in input_text or "dataWithLength:12u + utf8.length" in input_text:
        fail("text/composition GFX input helpers regressed to payload allocation")
    if "@property(nonatomic, strong) NSMapTable<UITouch*, NSNumber*>* orenTouchIDs" in renderer_text:
        fail("iOS renderer touch tracking must not retain per-touch NSNumber IDs")
    if "setObject:@(pointerID) forKey:touch" in renderer_text or "NSNumber* existing = [self.orenTouchIDs objectForKey:touch]" in renderer_text:
        fail("iOS renderer touch tracking must keep pointer IDs as raw scalars")
    if "OrenAVMGFXInputPointerIDForTouch" not in input_text or "OrenAVMGFXInputSendTouches" not in input_text:
        fail("CoreGraphics and Metal touch forwarding must share OrenAVMGFXInput helpers")
    if "CFDictionarySetValue(*touchIDs, (__bridge const void*)touch, (const void*)(uintptr_t)pointerID)" not in input_text:
        fail("shared iOS touch tracking must use pointer-keyed scalar maps")
    if "CFDictionarySetValue(_orenTouchIDs" in renderer_text or "orenPointerIDForTouch" in renderer_text:
        fail("iOS renderer touch map mutation must stay in OrenAVMGFXInput")
    if renderer_text.count("OrenAVMGFXInputSendPointerEvent(self.runtime,") != 2:
        fail("CoreGraphics and Metal pointer sends must delegate to the shared helper")
    if renderer_text.count("OrenAVMGFXInputSendPointerEvents(self.runtime,") != 2:
        fail("CoreGraphics and Metal pointer batches must delegate to the shared helper")
    if renderer_text.count("OrenAVMGFXInputSendTouches(self.runtime, self, &_orenTouchIDs, &_orenNextTouchID,") != 8:
        fail("CoreGraphics and Metal touch handlers must delegate to the shared helper")

    print("OK: iOS GFX input events use stack-first byte enqueue and shared scalar touch helpers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
