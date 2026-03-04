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
    r"\[list_hdr_ring_(recent|pre)\] list=(\d+) idx=(\d+) age=(\d+) op=(\d+) kind=(\d+) len=(-?\d+) cap=(-?\d+) buf=(\d+) magic=(-?\d+)"
)
CRASH_FOOTER_RING_RE = re.compile(
    r"\[crash_footer_raw\] ring idx=(\d+) list=(\d+) op=(\d+) len=(-?\d+) cap=(-?\d+) buf=(\d+) magic=(-?\d+) kind=(-?\d+)"
)
GC_FREE_RE = re.compile(
    r"\[gc_free_list\] ptr=(\d+) chunk=(\d+) kind=(\d+) len=(-?\d+) cap=(-?\d+) buf=(\d+) magic=(-?\d+)"
)
GC_REUSE_BAD_LIST_RE = re.compile(
    r"\[gc_reuse_bad_list\] .*ptr=(\d+)\b"
)
GC_LIST_CORRUPT_RE = re.compile(
    r"trace: gc (list(?:_int)?) corrupt list=(\d+) chunk=(\d+)"
)
LIST_CORRUPT_RE = re.compile(
    r"trace: list_corrupt stage=(\d+) list=(\d+) len=(-?\d+) cap=(-?\d+) buf=(\d+) magic=(-?\d+)"
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
    prefix = ""
    if "idx" in entry:
        prefix = f"idx={entry['idx']} "
    return (
        prefix +
        f"src={entry['src']} op={entry['op']} kind={entry['kind']} len={entry['len']} "
        f"cap={entry['cap']} buf={entry['buf']} magic={entry['magic']}"
    )

def fmt_recent(entry) -> str:
    return (
        f"src={entry['src']} idx={entry['idx']} age={entry['age']} op={entry['op']} "
        f"kind={entry['kind']} len={entry['len']} cap={entry['cap']} buf={entry['buf']} magic={entry['magic']}"
    )

def summarize_recent(entries, max_items=16) -> str:
    seq = []
    last = None
    for entry in entries:
        key = (entry["op"], entry["kind"])
        if key != last:
            seq.append(key)
            last = key
    if max_items > 0 and len(seq) > max_items:
        seq = seq[:max_items]
    return " -> ".join([f"{op}:{kind}" for op, kind in seq])

def compare_recent_sequences(seq_a, seq_b):
    if seq_a == seq_b:
        return None
    out = []
    max_len = max(len(seq_a), len(seq_b))
    for i in range(max_len):
        a = seq_a[i] if i < len(seq_a) else None
        b = seq_b[i] if i < len(seq_b) else None
        if a == b:
            continue
        if a is None:
            out.append(f"+{i}:{b[0]}:{b[1]}")
        elif b is None:
            out.append(f"-{i}:{a[0]}:{a[1]}")
        else:
            out.append(f"{i}:{a[0]}:{a[1]}->{b[0]}:{b[1]}")
    return out


def fmt_gc(entry) -> str:
    return (
        f"ptr={entry['ptr']} chunk={entry['chunk']} kind={entry['kind']} "
        f"len={entry['len']} cap={entry['cap']} buf={entry['buf']} magic={entry['magic']}"
    )

def fmt_list_corrupt(entry) -> str:
    return (
        f"stage={entry['stage']} list={entry['ptr']} len={entry['len']} cap={entry['cap']} "
        f"buf={entry['buf']} magic={entry['magic']}"
    )

def fmt_gc_list_corrupt(entry) -> str:
    return f"ptr={entry['ptr']} chunk={entry['chunk']}"


def main() -> int:
    args = parse_args()
    limit = max(1, args.limit)
    max_out = max(1, args.max)
    per_ptr = collections.defaultdict(lambda: collections.deque(maxlen=limit))
    per_ptr_ring = collections.defaultdict(list)
    per_ptr_recent = collections.defaultdict(list)
    per_ptr_recent_hits = collections.defaultdict(list)
    pending_bad_list_recent = collections.Counter()
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
                    per_ptr_ring[ptr].append(ring_entry)
                    if pending_gc is not None and pending_gc["ptr"] == ptr:
                        pending_gc["ring_entries"].append(ring_entry)
                    continue
                m = LIST_HDR_RING_RECENT_RE.search(line)
                if m:
                    (
                        tag,
                        ptr,
                        idx,
                        age,
                        op,
                        kind,
                        ln,
                        cap,
                        buf,
                        magic,
                    ) = m.groups()
                    ptr = int(ptr)
                    idx = int(idx)
                    age = int(age)
                    op = int(op)
                    kind = int(kind)
                    ln = int(ln)
                    cap = int(cap)
                    buf = int(buf)
                    magic = int(magic)
                    if ptr not in per_ptr_recent:
                        recent_order.append(ptr)
                    per_ptr_recent[ptr].append(
                        {
                            "src": f"list_hdr_ring_{tag}",
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
                    if pending_bad_list_recent[ptr] > 0:
                        per_ptr_recent_hits[ptr].append(
                            {
                                "src": "gc_reuse_bad_list_recent",
                                "entries": list(per_ptr_recent[ptr]),
                            }
                        )
                        pending_bad_list_recent[ptr] -= 1
                    continue

                m = CRASH_FOOTER_RING_RE.search(line)
                if m:
                    idx, ptr, op, ln, cap, buf, magic, kind = map(int, m.groups())
                    ring_entry = {
                        "src": "crash_footer_raw",
                        "idx": idx,
                        "op": op,
                        "kind": kind,
                        "len": ln,
                        "cap": cap,
                        "buf": buf,
                        "magic": magic,
                    }
                    per_ptr_ring[ptr].append(ring_entry)
                    if pending_gc is not None and pending_gc["ptr"] == ptr:
                        pending_gc["ring_entries"].append(ring_entry)
                    continue

                m = GC_REUSE_BAD_LIST_RE.search(line)
                if m:
                    ptr = int(m.group(1))
                    pending_bad_list_recent[ptr] += 1
                    if ptr in per_ptr_recent:
                        per_ptr_recent_hits[ptr].append(
                            {
                                "src": "gc_reuse_bad_list",
                                "entries": list(per_ptr_recent[ptr]),
                            }
                        )
                    continue

                m = GC_LIST_CORRUPT_RE.search(line)
                if m:
                    kind_tag, ptr, chunk = m.groups()
                    ptr = int(ptr)
                    chunk = int(chunk)
                    src = "gc_list_corrupt" if kind_tag == "list" else "gc_list_int_corrupt"
                    event = {
                        "src": src,
                        "ptr": ptr,
                        "chunk": chunk,
                        "entries": list(per_ptr.get(ptr, ())),
                        "ring_entries": list(per_ptr_ring.get(ptr, ())),
                    }
                    events.append(event)
                    if ptr in per_ptr_recent:
                        per_ptr_recent_hits[ptr].append(
                            {"src": src, "entries": list(per_ptr_recent[ptr])}
                        )
                    continue

                m = LIST_CORRUPT_RE.search(line)
                if m:
                    stage, ptr, ln, cap, buf, magic = map(int, m.groups())
                    event = {
                        "src": "list_corrupt",
                        "ptr": ptr,
                        "stage": stage,
                        "len": ln,
                        "cap": cap,
                        "buf": buf,
                        "magic": magic,
                        "entries": list(per_ptr.get(ptr, ())),
                        "ring_entries": list(per_ptr_ring.get(ptr, ())),
                    }
                    events.append(event)
                    if ptr in per_ptr_recent:
                        per_ptr_recent_hits[ptr].append(
                            {"src": "list_corrupt", "entries": list(per_ptr_recent[ptr])}
                        )
                    continue

                m = GC_FREE_RE.search(line)
                if not m:
                    continue
                ptr, chunk, kind, ln, cap, buf, magic = map(int, m.groups())
                if ptr in per_ptr_recent:
                    per_ptr_recent_hits[ptr].append(
                        {
                            "src": "gc_free_list",
                            "entries": list(per_ptr_recent[ptr]),
                        }
                    )
                event = {
                    "src": "gc_free_list",
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
        if event["src"] == "gc_free_list":
            print(f"[gc_free_list] {fmt_gc(event)}")
        elif event["src"] == "list_corrupt":
            print(f"[list_corrupt] {fmt_list_corrupt(event)}")
        elif event["src"] in ("gc_list_corrupt", "gc_list_int_corrupt"):
            print(f"[{event['src']}] {fmt_gc_list_corrupt(event)}")
        else:
            print(f"[{event['src']}] ptr={event['ptr']}")
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
            seq = summarize_recent(recent_entries)
            if seq:
                print(f"  list_hdr_ring_recent_seq count={len(recent_entries)} uniq={len(seq.split(' -> '))} ops={seq}")
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
            seq = summarize_recent(recent_entries)
            if seq:
                print(f"  list_hdr_ring_recent_seq count={len(recent_entries)} uniq={len(seq.split(' -> '))} ops={seq}")
            recent_emitted += 1
            if recent_emitted >= max_out:
                break

    if per_ptr_recent_hits:
        for ptr, hits in per_ptr_recent_hits.items():
            if len(hits) < 2:
                continue
            print(f"[list_hdr_ring_recent_delta] list={ptr} hits={len(hits)}")
            prev_seq = None
            for idx, entries in enumerate(hits):
                src = entries["src"]
                entries = entries["entries"]
                seq_pairs = []
                last = None
                for entry in entries:
                    key = (entry["op"], entry["kind"])
                    if key != last:
                        seq_pairs.append(key)
                        last = key
                if prev_seq is not None:
                    delta = compare_recent_sequences(prev_seq, seq_pairs)
                    if delta:
                        print(f"  delta hit={idx} src={src} changes={' '.join(delta)}")
                prev_seq = seq_pairs

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
