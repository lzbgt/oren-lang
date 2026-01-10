#!/usr/bin/env python3
"""
Minimal PE/COFF export-table checker (no external deps).

Purpose (rolling):
- Provide an offline sanity check that a PE32+ output produced by Oren's native backend
  contains the expected export names (e.g. `--lib` DLL exports, `@ffi.export` on EXE).
- Avoid relying on `dumpbin`, `llvm-objdump`, or remote execution.

This is intentionally narrow:
- supports PE32+ (x86_64) images
- only parses the Export Directory to list exported names

Usage:
  python3 scripts/pe_exports_check.py <path> --contains add --contains mul
  python3 scripts/pe_exports_check.py <path> --list
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path
from typing import Iterable, List, Optional, Tuple


class PEFormatError(RuntimeError):
    pass


def u16(b: bytes, off: int) -> int:
    return struct.unpack_from("<H", b, off)[0]


def u32(b: bytes, off: int) -> int:
    return struct.unpack_from("<I", b, off)[0]


def u64(b: bytes, off: int) -> int:
    return struct.unpack_from("<Q", b, off)[0]


def read_cstr(b: bytes, off: int) -> str:
    end = b.find(b"\x00", off)
    if end == -1:
        raise PEFormatError("unterminated c-string")
    return b[off:end].decode("ascii", errors="replace")


def parse_sections(b: bytes, pe_off: int, file_header_off: int, opt_header_size: int) -> List[Tuple[int, int, int, int]]:
    # Returns list of sections: (virt_addr, virt_size, raw_ptr, raw_size)
    num_sections = u16(b, file_header_off + 2)
    sec_table_off = file_header_off + 20 + opt_header_size
    sections: List[Tuple[int, int, int, int]] = []
    for i in range(num_sections):
        off = sec_table_off + i * 40
        if off + 40 > len(b):
            raise PEFormatError("section table truncated")
        virt_size = u32(b, off + 8)
        virt_addr = u32(b, off + 12)
        raw_size = u32(b, off + 16)
        raw_ptr = u32(b, off + 20)
        sections.append((virt_addr, virt_size, raw_ptr, raw_size))
    return sections


def rva_to_file_off(sections: List[Tuple[int, int, int, int]], rva: int) -> Optional[int]:
    for virt_addr, virt_size, raw_ptr, raw_size in sections:
        size = max(virt_size, raw_size)
        if rva >= virt_addr and rva < virt_addr + size:
            return raw_ptr + (rva - virt_addr)
    return None


def parse_pe_exports(path: Path) -> List[str]:
    b = path.read_bytes()
    if len(b) < 0x40:
        raise PEFormatError("file too small for DOS header")
    if b[0:2] != b"MZ":
        raise PEFormatError("missing MZ header")
    pe_off = u32(b, 0x3C)
    if pe_off + 4 + 20 > len(b):
        raise PEFormatError("PE header out of range")
    if b[pe_off : pe_off + 4] != b"PE\x00\x00":
        raise PEFormatError("missing PE signature")

    file_header_off = pe_off + 4
    machine = u16(b, file_header_off + 0)
    if machine != 0x8664:  # IMAGE_FILE_MACHINE_AMD64
        raise PEFormatError(f"unsupported machine: 0x{machine:04x} (expected amd64 0x8664)")

    opt_header_size = u16(b, file_header_off + 16)
    opt_off = file_header_off + 20
    if opt_off + opt_header_size > len(b):
        raise PEFormatError("optional header truncated")

    magic = u16(b, opt_off + 0)
    if magic != 0x20B:  # PE32+
        raise PEFormatError(f"unsupported optional header magic: 0x{magic:04x} (expected PE32+ 0x20b)")

    # DataDirectory starts at offset 0x70 in PE32+ Optional Header.
    data_dir_off = opt_off + 0x70
    if data_dir_off + 8 * 1 > opt_off + opt_header_size:
        raise PEFormatError("optional header missing data directory")
    export_rva = u32(b, data_dir_off + 0)
    export_size = u32(b, data_dir_off + 4)
    if export_rva == 0 or export_size == 0:
        return []

    sections = parse_sections(b, pe_off, file_header_off, opt_header_size)
    exp_off = rva_to_file_off(sections, export_rva)
    if exp_off is None:
        raise PEFormatError("cannot map export directory RVA to file offset")
    if exp_off + 40 > len(b):
        raise PEFormatError("export directory truncated")

    # IMAGE_EXPORT_DIRECTORY (40 bytes)
    number_of_names = u32(b, exp_off + 24)
    addr_of_names_rva = u32(b, exp_off + 32)
    addr_of_name_ordinals_rva = u32(b, exp_off + 36)
    if number_of_names == 0:
        return []

    names_off = rva_to_file_off(sections, addr_of_names_rva)
    ords_off = rva_to_file_off(sections, addr_of_name_ordinals_rva)
    if names_off is None or ords_off is None:
        raise PEFormatError("cannot map export name tables")
    if names_off + 4 * number_of_names > len(b):
        raise PEFormatError("export names table truncated")
    if ords_off + 2 * number_of_names > len(b):
        raise PEFormatError("export ordinals table truncated")

    names: List[str] = []
    for i in range(number_of_names):
        name_rva = u32(b, names_off + 4 * i)
        name_off = rva_to_file_off(sections, name_rva)
        if name_off is None:
            raise PEFormatError(f"cannot map export name RVA 0x{name_rva:x}")
        names.append(read_cstr(b, name_off))

    # Deterministic output.
    names = sorted(set(names))
    return names


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path)
    ap.add_argument("--contains", action="append", default=[], help="export name that must exist (repeatable)")
    ap.add_argument("--list", action="store_true", help="print all export names")
    args = ap.parse_args(argv)

    names = parse_pe_exports(args.path)
    if args.list:
        for n in names:
            print(n)

    missing = [n for n in args.contains if n not in names]
    if missing:
        print(f"ERROR: missing exports in {args.path}: {', '.join(missing)}", flush=True)
        if names:
            print("present exports:", ", ".join(names), flush=True)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

