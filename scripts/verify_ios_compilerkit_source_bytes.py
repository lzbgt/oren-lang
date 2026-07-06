#!/usr/bin/env python3
"""Verify CompilerKit compileSource builds source bytes without copy helpers."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPILERKIT = ROOT / "sdk/ios/OrenAVMKit/OrenAVMCompilerKit.m"


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def main() -> int:
    text = COMPILERKIT.read_text()
    forbidden = [
        "NSData* data = [source dataUsingEncoding:NSUTF8StringEncoding]",
        "[source dataUsingEncoding:NSUTF8StringEncoding]",
    ]
    for needle in forbidden:
        if needle in text:
            fail(f"CompilerKit compileSource must not regress to `{needle}`")
    required = [
        "enum { inlineSourceCap = 8192 }",
        "uint8_t inlineSource[inlineSourceCap]",
        "sourceBytes = byteLen <= inlineSourceCap ? inlineSource : (uint8_t*)malloc((size_t)byteLen)",
        "[source getBytes:sourceBytes",
        "[NSData dataWithBytesNoCopy:sourceBytes length:byteLen freeWhenDone:NO]",
        "if (sourceBytes != inlineSource) free(sourceBytes)",
    ]
    for needle in required:
        if needle not in text:
            fail(f"missing raw CompilerKit source byte evidence: `{needle}`")
    print("OK: CompilerKit compileSource uses stack-first raw UTF-8 source bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
