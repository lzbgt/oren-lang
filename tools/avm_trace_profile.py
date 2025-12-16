#!/usr/bin/env python3
import argparse
import binascii
import json
import sys
from dataclasses import dataclass
from typing import Dict, Optional, Tuple


def read_u8(b: bytes, i: int) -> Tuple[int, int]:
    if i + 1 > len(b):
        raise ValueError("truncated u8")
    return b[i], i + 1


def read_u16_le(b: bytes, i: int) -> Tuple[int, int]:
    if i + 2 > len(b):
        raise ValueError("truncated u16")
    return b[i] | (b[i + 1] << 8), i + 2


def read_u32_le(b: bytes, i: int) -> Tuple[int, int]:
    if i + 4 > len(b):
        raise ValueError("truncated u32")
    v = b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)
    return v, i + 4


@dataclass
class AllocInfo:
    kind: int
    size: int
    charged: int
    last_pc: int


def kind_name(k: int) -> str:
    return {
        0: "unknown",
        1: "string",
        2: "bytes",
        3: "list",
        4: "map",
        5: "vfs",
        6: "vproc",
        7: "vnet",
        8: "tmp",
    }.get(k, f"kind_{k}")


def parse_trace_bytes(trace: bytes) -> dict:
    if len(trace) < 8:
        raise ValueError("trace too short (missing header)")
    tag = trace[:8]
    if tag != b"AVMTRC02":
        raise ValueError(f"unsupported trace tag {tag!r} (expected b'AVMTRC02')")

    # Event ids (rolling, see lib/avm/avm.c):
    EVT_STEP = 1
    EVT_NATIVE2 = 2
    EVT_ABORT = 3
    EVT_ALLOC = 4
    EVT_FREE = 5
    EVT_REALLOC = 6

    i = 8
    allocs: Dict[int, AllocInfo] = {}
    live_charged = 0
    peak_live_charged = 0

    counts = {
        "step": 0,
        "native2": 0,
        "abort": 0,
        "alloc": 0,
        "free": 0,
        "realloc": 0,
        "unknown_event": 0,
    }

    # Totals (charged bytes are the "semantic heap budget" count).
    total_alloc_charged = 0
    total_free_charged = 0

    by_kind_total_alloc: Dict[int, int] = {}
    by_kind_peak_live: Dict[int, int] = {}
    by_kind_live: Dict[int, int] = {}

    def bump_kind(d: Dict[int, int], k: int, delta: int) -> None:
        d[k] = d.get(k, 0) + delta

    while i < len(trace):
        evt, i = read_u8(trace, i)

        if evt == EVT_STEP:
            # STEP: kind=u8(1), pc=u32, op=u8, ilen=u16, bytes[ilen]
            _, i = read_u32_le(trace, i)  # pc
            _, i = read_u8(trace, i)      # op
            ilen, i = read_u16_le(trace, i)
            if i + ilen > len(trace):
                raise ValueError("truncated STEP payload")
            i += ilen
            counts["step"] += 1
            continue

        if evt == EVT_NATIVE2:
            # NATIVE2: kind=u8(2), pc=u32, domain=u8, op=u16, nargs=u8
            _, i = read_u32_le(trace, i)  # pc
            _, i = read_u8(trace, i)      # domain
            _, i = read_u16_le(trace, i)  # op
            _, i = read_u8(trace, i)      # nargs
            counts["native2"] += 1
            continue

        if evt == EVT_ABORT:
            # ABORT: kind=u8(3), pc=u32, code=u16
            _, i = read_u32_le(trace, i)  # pc
            _, i = read_u16_le(trace, i)  # code
            counts["abort"] += 1
            continue

        if evt == EVT_ALLOC:
            # ALLOC (bytes-only): pc=u32, alloc_id=u32, alloc_kind=u8, size=u32, charged=u32
            pc, i = read_u32_le(trace, i)
            alloc_id, i = read_u32_le(trace, i)
            k, i = read_u8(trace, i)
            size, i = read_u32_le(trace, i)
            charged, i = read_u32_le(trace, i)

            counts["alloc"] += 1
            total_alloc_charged += charged

            # Treat duplicate alloc_id as overwrite (rolling behavior).
            prev = allocs.get(alloc_id)
            if prev is not None:
                # Adjust live bytes: remove previous, then add new.
                live_charged -= prev.charged
                bump_kind(by_kind_live, prev.kind, -prev.charged)

            allocs[alloc_id] = AllocInfo(kind=k, size=size, charged=charged, last_pc=pc)
            live_charged += charged
            bump_kind(by_kind_live, k, charged)
            bump_kind(by_kind_total_alloc, k, charged)
            peak_live_charged = max(peak_live_charged, live_charged)
            by_kind_peak_live[k] = max(by_kind_peak_live.get(k, 0), by_kind_live.get(k, 0))
            continue

        if evt == EVT_FREE:
            # FREE (bytes-only): pc=u32, alloc_id=u32, alloc_kind=u8, size=u32, charged=u32
            pc, i = read_u32_le(trace, i)
            alloc_id, i = read_u32_le(trace, i)
            k, i = read_u8(trace, i)
            size, i = read_u32_le(trace, i)
            charged, i = read_u32_le(trace, i)
            counts["free"] += 1

            info = allocs.pop(alloc_id, None)
            if info is not None:
                live_charged -= info.charged
                bump_kind(by_kind_live, info.kind, -info.charged)
                total_free_charged += info.charged
            else:
                # Free without prior alloc seen (e.g., trace budget truncated earlier).
                # Still count the declared charged bytes as freed for the event stream.
                total_free_charged += charged

            # pc/k/size are currently advisory; retain last seen pc if desired.
            _ = (pc, k, size)
            continue

        if evt == EVT_REALLOC:
            # REALLOC (bytes-only):
            # pc=u32, alloc_id=u32, alloc_kind=u8, old_size=u32, new_size=u32, old_charged=u32, new_charged=u32
            pc, i = read_u32_le(trace, i)
            alloc_id, i = read_u32_le(trace, i)
            k, i = read_u8(trace, i)
            _old_size, i = read_u32_le(trace, i)
            new_size, i = read_u32_le(trace, i)
            old_charged, i = read_u32_le(trace, i)
            new_charged, i = read_u32_le(trace, i)
            counts["realloc"] += 1

            info = allocs.get(alloc_id)
            if info is None:
                # Treat as allocate (trace may have been truncated before).
                allocs[alloc_id] = AllocInfo(kind=k, size=new_size, charged=new_charged, last_pc=pc)
                live_charged += new_charged
                bump_kind(by_kind_live, k, new_charged)
            else:
                live_charged -= info.charged
                bump_kind(by_kind_live, info.kind, -info.charged)
                info.kind = k
                info.size = new_size
                info.charged = new_charged
                info.last_pc = pc
                live_charged += new_charged
                bump_kind(by_kind_live, k, new_charged)

            peak_live_charged = max(peak_live_charged, live_charged)
            by_kind_peak_live[k] = max(by_kind_peak_live.get(k, 0), by_kind_live.get(k, 0))
            _ = old_charged  # reserved for more detailed accounting later
            continue

        counts["unknown_event"] += 1
        # Unknown event id: stop to avoid desync; schema is rolling.
        break

    # Produce a stable-ish report.
    kinds = sorted(set(list(by_kind_total_alloc.keys()) + list(by_kind_peak_live.keys()) + list(by_kind_live.keys())))
    kind_report = []
    for k in kinds:
        kind_report.append(
            {
                "kind": k,
                "name": kind_name(k),
                "total_alloc_charged": by_kind_total_alloc.get(k, 0),
                "peak_live_charged": by_kind_peak_live.get(k, 0),
                "live_charged": by_kind_live.get(k, 0),
            }
        )

    return {
        "schema": "avm.trace_profile.v1",
        "tag": tag.decode("ascii", errors="replace"),
        "counts": counts,
        "heap": {
            "total_alloc_charged": total_alloc_charged,
            "total_free_charged": total_free_charged,
            "peak_live_charged": peak_live_charged,
            "live_charged": live_charged,
            "live_allocs": len(allocs),
        },
        "by_kind": kind_report,
        "note": "ALLOC/FREE/REALLOC events are bytes-only (not included in TRACE_HASH) and may be truncated if AVM_TRACE_BYTES budget is exceeded.",
    }


def extract_hex_line(text: str) -> Optional[str]:
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("TRACE_BYTES_HEX "):
            return line.split(" ", 1)[1].strip()
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description="Decode AVM trace bytes and print a deterministic-ish allocation profile (memory leak/profiling helper).")
    ap.add_argument("--hex", help="Hex string for TRACE_BYTES_HEX payload.")
    ap.add_argument("--from-file", help="Read stdout of `./avm --print-trace-bytes-hex ...` from a file and extract TRACE_BYTES_HEX line.")
    ap.add_argument("--from-stdin", action="store_true", help="Read stdin and extract TRACE_BYTES_HEX line.")
    args = ap.parse_args()

    hex_s = args.hex
    if args.from_file:
        try:
            text = open(args.from_file, "r", encoding="utf-8", errors="replace").read()
        except OSError as e:
            print(f"error: failed to read {args.from_file}: {e}", file=sys.stderr)
            return 2
        hex_s = extract_hex_line(text)
        if not hex_s:
            print("error: TRACE_BYTES_HEX line not found in file", file=sys.stderr)
            return 2
    if args.from_stdin:
        text = sys.stdin.read()
        hex_s = extract_hex_line(text)
        if not hex_s:
            print("error: TRACE_BYTES_HEX line not found in stdin", file=sys.stderr)
            return 2

    if not hex_s:
        ap.print_usage(sys.stderr)
        return 2

    try:
        trace = binascii.unhexlify(hex_s.encode("ascii"))
    except (binascii.Error, ValueError) as e:
        print(f"error: invalid hex: {e}", file=sys.stderr)
        return 2

    try:
        report = parse_trace_bytes(trace)
    except Exception as e:
        print(f"error: failed to parse trace: {e}", file=sys.stderr)
        return 2

    json.dump(report, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

