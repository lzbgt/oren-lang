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
        description="Generate a readiness FAQ from STATUS.md sections."
    )
    parser.add_argument(
        "--status",
        default="docs/STATUS.md",
        help="Path to STATUS.md",
    )
    parser.add_argument(
        "--out-md",
        default="build/reports/status_faq.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/status_faq.json",
        help="Output JSON path",
    )
    return parser.parse_args()


def ensure_parent_dir(path: str) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)


def section_items(payload: Dict[str, Dict[str, List[str]]], key: str) -> List[str]:
    section = payload.get(key, {})
    items = section.get("items", [])
    return list(items) if isinstance(items, list) else []


def write_markdown(
    path: str, status_path: str, payload: Dict[str, Dict[str, List[str]]]
) -> None:
    ensure_parent_dir(path)
    generated_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Status FAQ\n\n")
        f.write("Generated from the current STATUS snapshot.\n\n")
        f.write(f"- source: `{status_path}`\n")
        f.write(f"- generated_at: {generated_at}\n\n")

        f.write("## Are the backends production-ready?\n\n")
        backend_items = section_items(payload, "backend_readiness")
        if not backend_items:
            f.write("- (no items found)\n\n")
        else:
            for item in backend_items:
                f.write(f"- {item}\n")
            f.write("\n")

        f.write("## Which feature readiness gaps are still open?\n\n")
        feature_items = section_items(payload, "feature_readiness_gaps")
        if not feature_items:
            f.write("- (no items found)\n\n")
        else:
            for item in feature_items:
                f.write(f"- {item}\n")
            f.write("\n")

        f.write("## What are the current production readiness gaps?\n\n")
        gap_items = section_items(payload, "production_readiness_gap")
        if not gap_items:
            f.write("- (no items found)\n\n")
        else:
            for item in gap_items:
                f.write(f"- {item}\n")
            f.write("\n")


def write_json(
    path: str, status_path: str, payload: Dict[str, Dict[str, List[str]]]
) -> None:
    ensure_parent_dir(path)
    generated_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    questions = [
        {
            "question": "Are the backends production-ready?",
            "section_key": "backend_readiness",
            "items": section_items(payload, "backend_readiness"),
        },
        {
            "question": "Which feature readiness gaps are still open?",
            "section_key": "feature_readiness_gaps",
            "items": section_items(payload, "feature_readiness_gaps"),
        },
        {
            "question": "What are the current production readiness gaps?",
            "section_key": "production_readiness_gap",
            "items": section_items(payload, "production_readiness_gap"),
        },
    ]
    out = {
        "source": status_path,
        "generated_at": generated_at,
        "questions": questions,
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
