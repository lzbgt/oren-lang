#!/usr/bin/env python3
"""Verify Oren arm64 Mach-O embedded debug-info table shape."""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path


MAX_FUNCS = 200_000
MAX_STR = 1 << 20
MAX_PARAMS = 1024


def align8(n: int) -> int:
    return (n + 7) & ~7


def u32(data: bytes, off: int) -> int:
    return struct.unpack_from("<I", data, off)[0]


def u64(data: bytes, off: int) -> int:
    return struct.unpack_from("<Q", data, off)[0]


def read_str(data: bytes, off: int) -> tuple[str, int] | None:
    if off + 8 > len(data):
        return None
    n = u64(data, off)
    if n > MAX_STR or off + 8 + n > len(data):
        return None
    raw = data[off + 8 : off + 8 + n]
    try:
        return raw.decode("utf-8"), align8(off + 8 + n)
    except UnicodeDecodeError:
        return None


def mach_o_segments(data: bytes) -> dict[str, tuple[int, int, int, int]]:
    if len(data) < 32 or u32(data, 0) != 0xFEEDFACF:
        raise ValueError("expected little-endian Mach-O 64")
    ncmds = u32(data, 16)
    off = 32
    out: dict[str, tuple[int, int, int, int]] = {}
    for _ in range(ncmds):
        if off + 8 > len(data):
            raise ValueError("truncated Mach-O load commands")
        cmd = u32(data, off)
        cmdsize = u32(data, off + 4)
        if cmdsize < 8 or off + cmdsize > len(data):
            raise ValueError("invalid Mach-O load command size")
        if cmd == 0x19:
            name = data[off + 8 : off + 24].split(b"\0", 1)[0].decode("ascii", "replace")
            out[name] = (
                u64(data, off + 24),
                u64(data, off + 32),
                u64(data, off + 40),
                u64(data, off + 48),
            )
        off += cmdsize
    return out


def parse_table(
    data: bytes,
    off: int,
    text_start: int,
    text_end: int,
) -> dict[str, object] | None:
    if off + 8 > len(data):
        return None
    count = u64(data, off)
    if count <= 0 or count > MAX_FUNCS:
        return None
    p = off + 8
    names: list[str] = []
    for _ in range(count):
        if p + 16 > len(data):
            return None
        start = u64(data, p)
        end = u64(data, p + 8)
        p += 16
        if not (text_start <= start < end <= text_end):
            return None
        name_r = read_str(data, p)
        if name_r is None:
            return None
        name, p = name_r
        file_r = read_str(data, p)
        if file_r is None:
            return None
        _file, p = file_r
        if p + 24 > len(data):
            return None
        _line = u64(data, p)
        _col = u64(data, p + 8)
        p_count = u64(data, p + 16)
        p += 24
        if p_count > MAX_PARAMS:
            return None
        for _ in range(p_count):
            param_r = read_str(data, p)
            if param_r is None:
                return None
            _param, p = param_r
            if p + 8 > len(data):
                return None
            p += 8
        names.append(name)
    return {"offset": off, "count": count, "end": p, "names": names}


def find_tables(data: bytes) -> list[dict[str, object]]:
    segs = mach_o_segments(data)
    if "__TEXT" not in segs or "__DATA" not in segs:
        raise ValueError("missing __TEXT or __DATA segment")
    text_vm, text_size, _text_file, _text_filesz = segs["__TEXT"]
    _data_vm, _data_size, data_file, data_filesz = segs["__DATA"]
    text_start = text_vm
    text_end = text_vm + text_size
    tables: list[dict[str, object]] = []
    for off in range(data_file, data_file + data_filesz - 8, 8):
        table = parse_table(data, off, text_start, text_end)
        if table is not None:
            tables.append(table)
    tables.sort(key=lambda t: int(t["count"]), reverse=True)
    return tables


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("binary", type=Path)
    ap.add_argument("--require-symbol", action="append", default=[])
    args = ap.parse_args(argv)

    data = args.binary.read_bytes()
    tables = find_tables(data)
    if not tables:
        print(f"no complete embedded debug-info table found in {args.binary}", file=sys.stderr)
        return 1
    table = tables[0]
    names = set(table["names"])
    missing = [name for name in args.require_symbol if name not in names]
    if missing:
        print(f"missing required symbols in first entries: {', '.join(missing)}", file=sys.stderr)
        return 1
    print(
        f"debug table OK: fileoff=0x{int(table['offset']):x} "
        f"count={int(table['count'])} first={','.join(table['names'][:16])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
