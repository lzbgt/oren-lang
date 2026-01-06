#!/usr/bin/env python3
"""
Resolve a program counter (PC) to a function name using Oren's embedded debug-info table.

This is intended for native debug builds where the binary is stripped (no Mach-O symbols),
but the compiler emitted a range-based debug-info table consumed by:
  lib/runtime_native/110_mem_diag.oren

Usage:
  scripts/resolve_native_pc.py <binary> <pc-hex-or-dec>

Example:
  scripts/resolve_native_pc.py build/tmp/capsule_ok_dbg 0x10000db1c
"""

from __future__ import annotations

import struct
import sys
from dataclasses import dataclass
from typing import Optional, Tuple


def _u64_le(buf: bytes, off: int) -> int:
    return struct.unpack_from("<Q", buf, off)[0]


def _align8(off: int) -> int:
    return (off + 7) & ~7


@dataclass(frozen=True)
class DebugEntry:
    start_pc: int
    end_pc: int
    name: str
    file: str
    line: int
    col: int


def _parse_one_entry(buf: bytes, off: int) -> Tuple[DebugEntry, int]:
    start_pc = _u64_le(buf, off)
    end_pc = _u64_le(buf, off + 8)
    name_len = _u64_le(buf, off + 16)
    if end_pc < start_pc:
        raise ValueError("dbginfo: end_pc < start_pc")
    if name_len > 64 * 1024:
        raise ValueError("dbginfo: absurd name_len")
    name_off = off + 24
    if name_off + name_len > len(buf):
        raise ValueError("dbginfo: name out of bounds")
    name_bytes = buf[name_off : name_off + name_len]
    try:
        name = name_bytes.decode("utf-8", errors="replace")
    except Exception:
        name = "<decode-failed>"

    p = _align8(name_off + name_len)

    if p + 8 > len(buf):
        raise ValueError("dbginfo: file_len out of bounds")
    file_len = _u64_le(buf, p)
    p += 8
    if file_len > 256 * 1024:
        raise ValueError("dbginfo: absurd file_len")
    if p + file_len > len(buf):
        raise ValueError("dbginfo: file out of bounds")
    file_bytes = buf[p : p + file_len]
    try:
        file = file_bytes.decode("utf-8", errors="replace")
    except Exception:
        file = ""
    p = _align8(p + file_len)

    if p + 16 > len(buf):
        raise ValueError("dbginfo: line/col out of bounds")
    line = _u64_le(buf, p)
    col = _u64_le(buf, p + 8)
    p += 16

    # params: [count][(name_len,name,align8,offset)*]
    if p + 8 > len(buf):
        raise ValueError("dbginfo: p_count out of bounds")
    p_count = _u64_le(buf, p)
    p += 8
    if p_count > 1024:
        raise ValueError("dbginfo: absurd p_count")
    for _ in range(p_count):
        if p + 8 > len(buf):
            raise ValueError("dbginfo: pname_len out of bounds")
        pname_len = _u64_le(buf, p)
        p += 8
        if pname_len > 64 * 1024:
            raise ValueError("dbginfo: absurd pname_len")
        if p + pname_len > len(buf):
            raise ValueError("dbginfo: pname out of bounds")
        p = _align8(p + pname_len)
        if p + 8 > len(buf):
            raise ValueError("dbginfo: param offset out of bounds")
        p += 8  # offset

    return DebugEntry(
        start_pc=start_pc, end_pc=end_pc, name=name, file=file, line=line, col=col
    ), p


def _try_parse_table_at(buf: bytes, table_off: int) -> Optional[Tuple[int, list[DebugEntry]]]:
    if table_off < 0 or table_off + 8 > len(buf):
        return None

    count = _u64_le(buf, table_off)
    # Sanity bounds: debug builds can have many functions, but not millions.
    if count == 0 or count > 1_000_000:
        return None

    entries: list[DebugEntry] = []
    p = table_off + 8
    try:
        for _ in range(count):
            e, p = _parse_one_entry(buf, p)
            entries.append(e)
            if p > len(buf):
                return None
    except (struct.error, IndexError):
        return None

    # Heuristic: table should contain the synthetic entry stub label.
    if not any(e.name == "__entry_stub__" for e in entries):
        return None

    return count, entries


def find_debug_table(buf: bytes) -> Tuple[int, list[DebugEntry]]:
    marker = b"__entry_stub__"
    want_len = len(marker)

    # Find an occurrence that looks like a debug-info entry name payload:
    # ... [start_pc][end_pc][name_len][name_bytes="__entry_stub__"] ...
    #
    # NOTE: the marker string can also appear as a pooled literal elsewhere in the binary
    # (e.g. compiler-side diagnostics). Do not assume the *first* occurrence is the table.
    pos = -1
    entry_off = -1
    scan_from = 0
    while True:
        pos = buf.find(marker, scan_from)
        if pos < 0:
            break
        cand = pos - 24
        scan_from = pos + 1
        if cand < 0:
            continue
        try:
            name_len0 = _u64_le(buf, cand + 16)
        except struct.error:
            continue
        if name_len0 == want_len:
            entry_off = cand
            break

    if entry_off < 0:
        raise SystemExit(
            "resolve_native_pc: '__entry_stub__' found, but no occurrence looked like a dbginfo entry"
        )

    # The marker entry's start_pc is the static address of the entry stub (code offset 0).
    # We use it as a strong sanity check when choosing among multiple candidate table starts.
    marker_start_pc = _u64_le(buf, entry_off)

    # We do NOT assume __entry_stub__ is the first entry (arm64 may not sort entries).
    # Instead, search backwards for a plausible table start:
    #
    # table layout:
    #   [count u64] [entry0] [entry1] ... [entryN-1]
    #
    # For a candidate table_off, parse entries sequentially until either:
    # - we see the marker entry, and return the fully parsed table
    # - we advance past the marker position without seeing it (candidate rejected)
    #
    # File sizes are small (debug builds); brute force is fine with strong heuristics.
    # The marker can appear inside the table multiple times (e.g. string pooling), and the byte
    # stream itself can contain false positives that look like a plausible `[count][entries...]`
    # prefix when scanning backwards.
    #
    # Instead of returning the first candidate that parses, scan all plausible candidates within
    # a bounded window and pick the one with the largest entry count (then smallest table_off).
    best: Optional[Tuple[int, list[DebugEntry]]] = None
    best_count = -1

    max_back = min(entry_off, 256 * 1024)
    for back in range(8, max_back + 1, 8):
        table_off = entry_off - back
        if table_off < 0:
            break

        try:
            count = _u64_le(buf, table_off)
        except struct.error:
            continue
        if count == 0 or count > 200_000:
            continue

        entries: list[DebugEntry] = []
        p = table_off + 8
        saw_marker = False
        ok = True
        try:
            for _ in range(count):
                # Parse minimal + skip. Validate shape to prune false positives.
                start_pc = _u64_le(buf, p)
                end_pc = _u64_le(buf, p + 8)
                name_len0 = _u64_le(buf, p + 16)
                name_off = p + 24
                if end_pc < start_pc:
                    ok = False
                    break
                if name_len0 > 4_096:
                    ok = False
                    break
                if name_off + name_len0 > len(buf):
                    ok = False
                    break
                name_bytes = buf[name_off : name_off + name_len0]
                if name_bytes == marker:
                    saw_marker = True

                # Now parse full entry so caller can resolve PCs.
                try:
                    e, p2 = _parse_one_entry(buf, p)
                except ValueError:
                    ok = False
                    break
                entries.append(e)
                p = p2

                # Once the parser cursor moves past the marker position and we haven't seen
                # the marker entry, this table_off cannot be the correct start.
                if p > pos and not saw_marker:
                    ok = False
                    break
            if ok and saw_marker:
                # Strong sanity: a correct table must include the entry stub at the lowest
                # start_pc, because the entry stub begins at code offset 0.
                min_start_pc = min(e.start_pc for e in entries) if entries else 0
                if min_start_pc != marker_start_pc:
                    continue
                if count > best_count or (
                    count == best_count and best is not None and table_off < best[0]
                ):
                    best = (table_off, entries)
                    best_count = int(count)
        except (struct.error, IndexError, OverflowError):
            continue

    if best is None:
        raise SystemExit("resolve_native_pc: failed to locate embedded debug-info table")
    return best


def resolve_pc(entries: list[DebugEntry], pc: int) -> Optional[DebugEntry]:
    # Entries are emitted sorted by increasing start_pc, but don't rely on it too hard.
    for e in entries:
        if pc >= e.start_pc and pc < e.end_pc:
            return e
    return None


def parse_pc(s: str) -> int:
    s = s.strip().lower()
    if s.startswith("0x"):
        return int(s, 16)
    return int(s, 10)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    path = argv[1]
    pc = parse_pc(argv[2])
    with open(path, "rb") as f:
        buf = f.read()

    _table_off, entries = find_debug_table(buf)
    hit = resolve_pc(entries, pc)
    if hit is None:
        print("???")
        return 1

    loc = ""
    if hit.file and hit.line and hit.col:
        loc = f" {hit.file}:{hit.line}:{hit.col}"
    print(f"{hit.name}{loc} [0x{hit.start_pc:x}..0x{hit.end_pc:x})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
