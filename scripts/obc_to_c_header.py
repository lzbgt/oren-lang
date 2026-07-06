#!/usr/bin/env python3
"""Emit an OBC byte payload as a tiny C include header."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("symbol")
    args = parser.parse_args()

    data = args.input.read_bytes()
    chunks = []
    for i in range(0, len(data), 12):
        chunks.append(", ".join(f"0x{b:02x}" for b in data[i:i + 12]))
    args.output.write_text(
        "#include <stddef.h>\n"
        f"static const unsigned char {args.symbol}[] = {{\n"
        + ",\n".join("    " + chunk for chunk in chunks)
        + "\n};\n"
        + f"static const size_t {args.symbol}Len = {len(data)}u;\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
