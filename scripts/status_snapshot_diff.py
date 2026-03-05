#!/usr/bin/env python3
import argparse
import json
import os
import sys
from datetime import datetime
from typing import Any, Dict, List, Tuple

from status_item_format import format_multiline_item, items_from_section
from status_snapshot_lib import SECTION_MATCHES, snapshot_from_status


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Diff status snapshots or STATUS.md files."
    )
    parser.add_argument("--left", required=True, help="Left STATUS.md or snapshot JSON")
    parser.add_argument("--right", required=True, help="Right STATUS.md or snapshot JSON")
    parser.add_argument(
        "--out-md",
        default="build/reports/status_snapshot_diff.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/status_snapshot_diff.json",
        help="Output JSON path",
    )
    return parser.parse_args()


def ensure_parent_dir(path: str) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)


def load_snapshot_json(path: str) -> Dict[str, Dict[str, Any]]:
    with open(path, "r", encoding="utf-8") as f:
        payload = json.load(f)
    if not isinstance(payload, dict):
        raise ValueError("snapshot JSON must be an object")
    if "sections" in payload and isinstance(payload["sections"], dict):
        return payload["sections"]
    return payload  # allow raw sections dict


def load_sections(path: str) -> Dict[str, Dict[str, Any]]:
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    if path.endswith(".json"):
        return load_snapshot_json(path)
    try:
        with open(path, "r", encoding="utf-8") as f:
            first = f.read(1)
        if first == "{":
            return load_snapshot_json(path)
    except Exception:
        pass
    return snapshot_from_status(path)


def diff_items(left_items: List[str], right_items: List[str]) -> Tuple[List[str], List[str]]:
    left_set = set(left_items)
    right_set = set(right_items)
    added = [item for item in right_items if item not in left_set]
    removed = [item for item in left_items if item not in right_set]
    return added, removed


def build_diff(left: Dict[str, Dict[str, Any]], right: Dict[str, Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    diff: Dict[str, Dict[str, Any]] = {}
    for key in SECTION_MATCHES.keys():
        left_section = left.get(key, {})
        right_section = right.get(key, {})
        left_items = items_from_section(left_section)
        right_items = items_from_section(right_section)
        added, removed = diff_items(left_items, right_items)
        diff[key] = {
            "title": right_section.get("title") or left_section.get("title") or key,
            "added": added,
            "removed": removed,
            "left_count": len(left_items),
            "right_count": len(right_items),
        }
    return diff


def write_markdown(path: str, left_path: str, right_path: str, diff: Dict[str, Dict[str, Any]]) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Status snapshot diff\n\n")
        f.write(f"- left: `{left_path}`\n")
        f.write(f"- right: `{right_path}`\n")
        f.write(f"- generated_at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        for key, section in diff.items():
            f.write(f"## {section.get('title', key)}\n\n")
            added = section.get("added", [])
            removed = section.get("removed", [])
            f.write(f"- left_count: {section.get('left_count', 0)}\n")
            f.write(f"- right_count: {section.get('right_count', 0)}\n\n")
            f.write("Added:\n\n")
            if added:
                for item in added:
                    for line in format_multiline_item(item):
                        f.write(f"{line}\n")
            else:
                f.write("- (none)\n")
            f.write("\nRemoved:\n\n")
            if removed:
                for item in removed:
                    for line in format_multiline_item(item):
                        f.write(f"{line}\n")
            else:
                f.write("- (none)\n")
            f.write("\n")


def write_json(path: str, left_path: str, right_path: str, diff: Dict[str, Dict[str, Any]]) -> None:
    ensure_parent_dir(path)
    payload = {
        "left": left_path,
        "right": right_path,
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "sections": diff,
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, sort_keys=True)
        f.write("\n")


def main() -> int:
    args = parse_args()
    try:
        left_sections = load_sections(args.left)
    except Exception as exc:
        print(f"ERROR: failed to load left snapshot: {exc}", file=sys.stderr)
        return 2
    try:
        right_sections = load_sections(args.right)
    except Exception as exc:
        print(f"ERROR: failed to load right snapshot: {exc}", file=sys.stderr)
        return 2

    diff = build_diff(left_sections, right_sections)
    write_markdown(args.out_md, args.left, args.right, diff)
    write_json(args.out_json, args.left, args.right, diff)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
