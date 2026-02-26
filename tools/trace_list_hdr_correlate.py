#!/usr/bin/env python3
import argparse
import collections
import re
import sys


LIST_HDR_RE = re.compile(
    r"\[list_hdr\] op=(\d+) list=(\d+) kind=(\d+) len=(-?\d+) cap=(-?\d+) buf=(\d+) magic=(-?\d+)"
)
LIST_HDR_RING_RE = re.compile(
    r"\[list_hdr_ring\] (?:idx=\d+\s+)?list=(\d+) op=(\d+) kind=(\d+) len=(-?\d+) cap=(-?\d+) buf=(\d+) magic=(-?\d+)"
)
LIST_HDR_RING_RECENT_RE = re.compile(
    r"\[list_hdr_ring_recent\] list=(\d+) idx=(\d+) age=(\d+) op=(\d+) kind=(\d+) len=(-?\d+) cap=(-?\d+) buf=(\d+) magic=(-?\d+)"
)
GC_FREE_RE = re.compile(
    r"\[gc_free_list\] ptr=(\d+) chunk=(\d+) kind=(\d+) len=(-?\d+) cap=(-?\d+) buf=(\d+) magic=(-?\d+)"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Correlate list_hdr traces with gc_free_list samples.",
    )
    parser.add_argument("--log", required=True, help="Path to a log file.")
    parser.add_argument(
        "--limit",
        type=int,
        default=5,
        help="Max list_hdr entries to keep per list pointer (default: 5).",
    )
    parser.add_argument(
        "--max",
        type=int,
        default=50,
        help="Max gc_free_list entries to emit (default: 50).",
    )
    return parser.parse_args()


def fmt_hdr(entry) -> str:
    return (
        f"src={entry['src']} op={entry['op']} kind={entry['kind']} len={entry['len']} "
        f"cap={entry['cap']} buf={entry['buf']} magic={entry['magic']}"
    )

def fmt_recent(entry) -> str:
    return (
        f"src={entry['src']} idx={entry['idx']} age={entry['age']} op={entry['op']} "
        f"kind={entry['kind']} len={entry['len']} cap={entry['cap']} buf={entry['buf']} magic={entry['magic']}"
    )


def fmt_gc(entry) -> str:
    return (
        f"ptr={entry['ptr']} chunk={entry['chunk']} kind={entry['kind']} "
        f"len={entry['len']} cap={entry['cap']} buf={entry['buf']} magic={entry['magic']}"
    )


def main() -> int:
    args = parse_args()
    limit = max(1, args.limit)
    max_out = max(1, args.max)
    per_ptr = collections.defaultdict(lambda: collections.deque(maxlen=limit))
    per_ptr_recent = collections.defaultdict(list)
    recent_order = []
    events = []
    pending_gc = None

    try:
        with open(args.log, "r", encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                m = LIST_HDR_RE.search(line)
                if m:
                    op, ptr, kind, ln, cap, buf, magic = map(int, m.groups())
                    per_ptr[ptr].append(
                        {
                            "src": "list_hdr",
                            "op": op,
                            "kind": kind,
                            "len": ln,
                            "cap": cap,
                            "buf": buf,
                            "magic": magic,
                        }
                    )
                    continue
                m = LIST_HDR_RING_RE.search(line)
                if m:
                    ptr, op, kind, ln, cap, buf, magic = map(int, m.groups())
                    ring_entry = {
                        "src": "list_hdr_ring",
                        "op": op,
                        "kind": kind,
                        "len": ln,
                        "cap": cap,
                        "buf": buf,
                        "magic": magic,
                    }
                    if pending_gc is not None and pending_gc["ptr"] == ptr:
                        pending_gc["ring_entries"].append(ring_entry)
                    continue
                m = LIST_HDR_RING_RECENT_RE.search(line)
                if m:
                    (
                        ptr,
                        idx,
                        age,
                        op,
                        kind,
                        ln,
                        cap,
                        buf,
                        magic,
                    ) = map(int, m.groups())
                    if ptr not in per_ptr_recent:
                        recent_order.append(ptr)
                    per_ptr_recent[ptr].append(
                        {
                            "src": "list_hdr_ring_recent",
                            "idx": idx,
                            "age": age,
                            "op": op,
                            "kind": kind,
                            "len": ln,
                            "cap": cap,
                            "buf": buf,
                            "magic": magic,
                        }
                    )
                    continue

                m = GC_FREE_RE.search(line)
                if not m:
                    continue
                ptr, chunk, kind, ln, cap, buf, magic = map(int, m.groups())
                event = {
                    "ptr": ptr,
                    "chunk": chunk,
                    "kind": kind,
                    "len": ln,
                    "cap": cap,
                    "buf": buf,
                    "magic": magic,
                    "entries": list(per_ptr.get(ptr, ())),
                    "ring_entries": [],
                }
                events.append(event)
                pending_gc = event
    except OSError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    emitted = 0
    recent_emitted = 0
    printed_recent_ptrs = set()
    for event in events:
        emitted += 1
        print(f"[gc_free_list] {fmt_gc(event)}")
        entries = event["entries"]
        ring_entries = event["ring_entries"]
        recent_entries = per_ptr_recent.get(event["ptr"], [])
        if not entries and not ring_entries:
            print("  list_hdr: none")
        else:
            for idx, entry in enumerate(entries):
                print(f"  list_hdr[{idx}] {fmt_hdr(entry)}")
            for idx, entry in enumerate(ring_entries):
                print(f"  list_hdr_ring[{idx}] {fmt_hdr(entry)}")
        if recent_entries:
            for idx, entry in enumerate(recent_entries):
                print(f"  list_hdr_ring_recent[{idx}] {fmt_recent(entry)}")
            printed_recent_ptrs.add(event["ptr"])
        if emitted >= max_out:
            break

    if recent_order and recent_emitted < max_out:
        for ptr in recent_order:
            if ptr in printed_recent_ptrs:
                continue
            recent_entries = per_ptr_recent.get(ptr, [])
            if not recent_entries:
                continue
            print(f"[list_hdr_ring_recent_only] list={ptr}")
            for idx, entry in enumerate(recent_entries):
                print(f"  list_hdr_ring_recent[{idx}] {fmt_recent(entry)}")
            recent_emitted += 1
            if recent_emitted >= max_out:
                break

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
