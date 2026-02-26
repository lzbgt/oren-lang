#!/usr/bin/env python3
import argparse
import collections
import re
import sys


LIST_HDR_RE = re.compile(
    r"\\[list_hdr\\] op=(\\d+) list=(\\d+) kind=(\\d+) len=(-?\\d+) cap=(-?\\d+) buf=(\\d+) magic=(-?\\d+)"
)
GC_FREE_RE = re.compile(
    r"\\[gc_free_list\\] ptr=(\\d+) chunk=(\\d+) kind=(\\d+) len=(-?\\d+) cap=(-?\\d+) buf=(\\d+) magic=(-?\\d+)"
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
        f"op={entry['op']} kind={entry['kind']} len={entry['len']} "
        f"cap={entry['cap']} buf={entry['buf']} magic={entry['magic']}"
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
    emitted = 0

    try:
        with open(args.log, "r", encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                m = LIST_HDR_RE.search(line)
                if m:
                    op, ptr, kind, ln, cap, buf, magic = map(int, m.groups())
                    per_ptr[ptr].append(
                        {
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
                emitted += 1
                print(f"[gc_free_list] {fmt_gc({'ptr': ptr, 'chunk': chunk, 'kind': kind, 'len': ln, 'cap': cap, 'buf': buf, 'magic': magic})}")
                entries = list(per_ptr.get(ptr, ()))
                if not entries:
                    print("  list_hdr: none")
                else:
                    for idx, entry in enumerate(entries):
                        print(f"  list_hdr[{idx}] {fmt_hdr(entry)}")
                if emitted >= max_out:
                    break
    except OSError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
