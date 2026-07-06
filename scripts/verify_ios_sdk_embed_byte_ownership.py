#!/usr/bin/env python3
"""Verify iOS SDK takes ownership of returned embedder byte buffers without recopying."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
SDK_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMKit.m"
RUNTIME_TYPES_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMRuntimeTypes.m"
PACKAGE_STORE_SOURCE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMPackageStore.m"
EMBED_SOURCE = ROOT / "lib/avm/avm_embed.c"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    sdk = SDK_SOURCE.read_text()
    runtime_types = RUNTIME_TYPES_SOURCE.read_text()
    package_store = PACKAGE_STORE_SOURCE.read_text()
    embed = EMBED_SOURCE.read_text()

    if "void avm_embed_free_bytes(uint8_t* data) {\n    free(data);\n}" not in embed:
        fail("avm_embed_free_bytes must remain malloc/free compatible for NSData no-copy ownership")
    if "static NSData* OrenAVMKitDataTakingEmbedBytes" not in sdk:
        fail("missing SDK embed-byte ownership helper")
    if "dataWithBytesNoCopy:bytes length:len freeWhenDone:YES" not in sdk:
        fail("embed-byte ownership helper must use no-copy NSData construction")

    forbidden_patterns = [
        r"NSData\*\s+\w+\s*=\s*\[NSData dataWithBytes:bytes length:len\];\s*avm_embed_free_bytes\(bytes\);",
        r"stdoutData\s*=\s*\[NSData dataWithBytes:stdoutBytes length:stdoutLen\];\s*avm_embed_free_bytes\(stdoutBytes\);",
    ]
    for pattern in forbidden_patterns:
        if re.search(pattern, sdk, flags=re.MULTILINE):
            fail("SDK embedder byte getters must transfer buffers to NSData instead of copy/free")

    helper_uses = sdk.count("OrenAVMKitDataTakingEmbedBytes(") - 1
    if helper_uses != 4:
        fail(f"expected 4 embed-byte helper uses, found {helper_uses}")
    if "_stdoutData = [stdoutData copy]" in runtime_types:
        fail("OrenAVMRunResult must not recopy immutable no-copy stdout NSData")
    if "[stdoutData isKindOfClass:[NSMutableData class]] ? [stdoutData copy]" not in runtime_types:
        fail("OrenAVMRunResult must copy only mutable stdout inputs")
    if "body = [NSData dataWithBytes:compressed length:uncompressedSize]" in package_store:
        fail("stored ZIP entries must borrow the release-bundle slice instead of copying it")
    if "body = [NSData dataWithBytesNoCopy:(void*)compressed length:uncompressedSize freeWhenDone:NO]" not in package_store:
        fail("stored ZIP entries must use no-copy NSData over borrowed release-bundle bytes")

    print("OK: iOS SDK embed byte getters use no-copy NSData ownership")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
