#!/usr/bin/env python3
import argparse
import json
import os
import sys
from datetime import datetime
from typing import Dict, List

from status_snapshot_lib import snapshot_from_status


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Snapshot key readiness status sections into markdown + JSON."
    )
    parser.add_argument(
        "--status",
        default="docs/STATUS.md",
        help="Path to STATUS.md",
    )
    parser.add_argument(
        "--out-md",
        default="build/reports/status_snapshot.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/status_snapshot.json",
        help="Output JSON path",
    )
    return parser.parse_args()


def ensure_parent_dir(path: str) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)


def write_markdown(path: str, status_path: str, payload: Dict[str, Dict[str, List[str]]]) -> None:
    ensure_parent_dir(path)
    generated_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Status snapshot\n\n")
        f.write(f"- source: `{status_path}`\n")
        f.write(f"- generated_at: {generated_at}\n\n")
        for key in ("production_readiness_gap", "backend_readiness", "feature_readiness_gaps"):
            section = payload.get(key, {})
            title = section.get("title", key)
            items = section.get("items", [])
            f.write(f"## {title}\n\n")
            if not items:
                f.write("- (no items found)\n\n")
                continue
            for item in items:
                f.write(f"- {item}\n")
            f.write("\n")


def write_json(path: str, status_path: str, payload: Dict[str, Dict[str, List[str]]]) -> None:
    ensure_parent_dir(path)
    out = {
        "source": status_path,
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "sections": payload,
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, sort_keys=True)
        f.write("\n")


def main() -> int:
    args = parse_args()
    if not os.path.exists(args.status):
        print(f"ERROR: status file not found or empty: {args.status}", file=sys.stderr)
        return 2
    payload = snapshot_from_status(args.status)
    write_markdown(args.out_md, args.status, payload)
    write_json(args.out_json, args.status, payload)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
