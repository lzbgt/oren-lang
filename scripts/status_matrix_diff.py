#!/usr/bin/env python3
import argparse
import json
import os
import sys
from datetime import datetime
from typing import Any, Dict, List

from status_item_format import format_multiline_item
from status_matrix_lib import SECTION_ORDER, SECTION_TITLES, matrix_from_status, row_identity


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Diff status matrix outputs or STATUS.md files."
    )
    parser.add_argument("--left", required=True, help="Left STATUS.md or matrix JSON")
    parser.add_argument("--right", required=True, help="Right STATUS.md or matrix JSON")
    parser.add_argument(
        "--out-md",
        default="build/reports/status_matrix_diff.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/status_matrix_diff.json",
        help="Output JSON path",
    )
    return parser.parse_args()


def ensure_parent_dir(path: str) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)


def load_matrix_json(path: str) -> Dict[str, List[Dict[str, Any]]]:
    with open(path, "r", encoding="utf-8") as f:
        payload = json.load(f)
    if not isinstance(payload, dict):
        raise ValueError("matrix JSON must be an object")
    if "sections" in payload and isinstance(payload["sections"], dict):
        return payload["sections"]
    return payload


def load_matrix(path: str) -> Dict[str, List[Dict[str, Any]]]:
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    if path.endswith(".json"):
        return load_matrix_json(path)
    try:
        with open(path, "r", encoding="utf-8") as f:
            first = f.read(1)
        if first == "{":
            return load_matrix_json(path)
    except Exception:
        pass
    return matrix_from_status(path)


def diff_rows(left_rows: List[Dict[str, Any]], right_rows: List[Dict[str, Any]]) -> Dict[str, List[str]]:
    left_ids = [row_identity(row) for row in left_rows]
    right_ids = [row_identity(row) for row in right_rows]
    left_set = set(left_ids)
    right_set = set(right_ids)
    added = [row for row in right_ids if row not in left_set]
    removed = [row for row in left_ids if row not in right_set]
    return {
        "added": added,
        "removed": removed,
        "left_count": len(left_rows),
        "right_count": len(right_rows),
    }


def build_diff(
    left: Dict[str, List[Dict[str, Any]]],
    right: Dict[str, List[Dict[str, Any]]],
) -> Dict[str, Dict[str, Any]]:
    diff: Dict[str, Dict[str, Any]] = {}
    for key in SECTION_ORDER:
        left_rows = list(left.get(key, []))
        right_rows = list(right.get(key, []))
        section_diff = diff_rows(left_rows, right_rows)
        section_diff["title"] = SECTION_TITLES.get(key, key)
        diff[key] = section_diff
    return diff


def write_markdown(path: str, left_path: str, right_path: str, diff: Dict[str, Dict[str, Any]]) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Status matrix diff\n\n")
        f.write(f"- left: `{left_path}`\n")
        f.write(f"- right: `{right_path}`\n")
        f.write(f"- generated_at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        for key in SECTION_ORDER:
            section = diff.get(key, {})
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
        left_matrix = load_matrix(args.left)
    except Exception as exc:
        print(f"ERROR: failed to load left matrix: {exc}", file=sys.stderr)
        return 2
    try:
        right_matrix = load_matrix(args.right)
    except Exception as exc:
        print(f"ERROR: failed to load right matrix: {exc}", file=sys.stderr)
        return 2

    diff = build_diff(left_matrix, right_matrix)
    write_markdown(args.out_md, args.left, args.right, diff)
    write_json(args.out_json, args.left, args.right, diff)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
