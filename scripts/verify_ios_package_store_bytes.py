#!/usr/bin/env python3
"""Verify iOS package-store byte helpers avoid avoidable wrapper allocations."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE_STORE = ROOT / "sdk/ios/OrenAVMKit/OrenAVMPackageStore.m"


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def main() -> int:
    text = PACKAGE_STORE.read_text()
    forbidden = [
        "NSMutableData* out = [NSMutableData dataWithLength:hex.length / 2u]",
        "NSString* part = [hex substringWithRange:NSMakeRange(i, 2u)]",
        "NSScanner* scanner = [NSScanner scannerWithString:part]",
        "NSMutableData* out = [NSMutableData dataWithLength:outputLen]",
        "stream.next_out = out.mutableBytes",
        "NSData* signedMessage = [manifestHash.lowercaseString dataUsingEncoding:NSUTF8StringEncoding]",
    ]
    for needle in forbidden:
        if needle in text:
            fail(f"package-store byte helper must not regress to `{needle}`")
    required = [
        "static int OrenAVMPackageHexNibble",
        "uint8_t* bytes = (uint8_t*)malloc((size_t)byteLen)",
        "return [NSData dataWithBytesNoCopy:bytes length:byteLen freeWhenDone:YES]",
        "uint8_t* output = outputLen > 0 ? (uint8_t*)malloc((size_t)outputLen) : NULL",
        "stream.next_out = output",
        "return [NSData dataWithBytesNoCopy:output length:outputLen freeWhenDone:YES]",
        "uint8_t signedMessageBytes[64]",
        "[NSData dataWithBytesNoCopy:signedMessageBytes length:signedMessageLen freeWhenDone:NO]",
    ]
    for needle in required:
        if needle not in text:
            fail(f"missing raw package-store byte helper evidence: `{needle}`")
    print("OK: iOS package store byte helpers use raw/no-copy buffers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
