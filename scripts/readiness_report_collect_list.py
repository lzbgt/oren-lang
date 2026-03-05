#!/usr/bin/env python3
import argparse
import json
import os
import sys
from typing import Any, Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="List readiness report collection snapshots."
    )
    parser.add_argument(
        "--dir",
        default="build/reports/readiness_collect",
        help="Collection directory",
    )
    parser.add_argument(
        "--out",
        default="build/reports/readiness_collect_index.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/readiness_collect_index.json",
        help="Output JSON path",
    )
    return parser.parse_args()


def ensure_parent_dir(path: str) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)


def load_snapshot(path: str) -> Dict[str, Any]:
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, dict) else {}


def main() -> int:
    args = parse_args()
    if not os.path.exists(args.dir):
        print(f"WARN: collection dir not found: {args.dir}", file=sys.stderr)
        ensure_parent_dir(args.out)
        with open(args.out, "w", encoding="utf-8") as f:
            f.write("# Readiness collection\n\n- (none)\n")
        ensure_parent_dir(args.out_json)
        with open(args.out_json, "w", encoding="utf-8") as f:
            json.dump({"total": 0, "entries": []}, f, indent=2, sort_keys=True)
            f.write("\n")
        return 0

    entries: List[Dict[str, Any]] = []
    for name in sorted(os.listdir(args.dir)):
        snapshot_dir = os.path.join(args.dir, name)
        if not os.path.isdir(snapshot_dir):
            continue
        meta = load_snapshot(os.path.join(snapshot_dir, "snapshot.json"))
        if not meta:
            continue
        meta["snapshot_dir"] = snapshot_dir
        entries.append(meta)

    ensure_parent_dir(args.out)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("# Readiness collection\n\n")
        if not entries:
            f.write("- (none)\n")
        else:
            f.write("| Timestamp | Profile | Tag | Overall | Snapshot Dir |\n")
            f.write("| --- | --- | --- | --- | --- |\n")
            for meta in entries:
                f.write(
                    f"| {meta.get('timestamp','-')} | {meta.get('profile','-')} | {meta.get('tag','-')} | "
                    f"{meta.get('overall','-')} | {meta.get('snapshot_dir','-')} |\n"
                )

    ensure_parent_dir(args.out_json)
    with open(args.out_json, "w", encoding="utf-8") as f:
        json.dump({"total": len(entries), "entries": entries}, f, indent=2, sort_keys=True)
        f.write("\n")

    print(f"OK: wrote {args.out} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
