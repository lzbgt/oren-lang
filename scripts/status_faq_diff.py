#!/usr/bin/env python3
import argparse
import json
import os
import sys
from datetime import datetime
from typing import Any, Dict, List, Tuple

from status_faq import build_questions
from status_snapshot_lib import snapshot_from_status


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Diff status FAQ outputs or STATUS.md files."
    )
    parser.add_argument("--left", required=True, help="Left STATUS.md or FAQ JSON")
    parser.add_argument("--right", required=True, help="Right STATUS.md or FAQ JSON")
    parser.add_argument(
        "--out-md",
        default="build/reports/status_faq_diff.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/status_faq_diff.json",
        help="Output JSON path",
    )
    return parser.parse_args()


def ensure_parent_dir(path: str) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)


def load_questions_from_json(path: str) -> List[Dict[str, Any]]:
    with open(path, "r", encoding="utf-8") as f:
        payload = json.load(f)
    if not isinstance(payload, dict):
        raise ValueError("FAQ JSON must be an object")
    questions = payload.get("questions")
    if isinstance(questions, list):
        return questions
    sections = payload.get("sections")
    if isinstance(sections, dict):
        return build_questions(sections)
    raise ValueError("FAQ JSON missing questions")


def load_questions(path: str) -> List[Dict[str, Any]]:
    if not os.path.exists(path):
        raise FileNotFoundError(path)
    if path.endswith(".json"):
        return load_questions_from_json(path)
    try:
        with open(path, "r", encoding="utf-8") as f:
            first = f.read(1)
        if first == "{":
            return load_questions_from_json(path)
    except Exception:
        pass
    sections = snapshot_from_status(path)
    return build_questions(sections)


def diff_items(left_items: List[str], right_items: List[str]) -> Tuple[List[str], List[str]]:
    left_set = set(left_items)
    right_set = set(right_items)
    added = [item for item in right_items if item not in left_set]
    removed = [item for item in left_items if item not in right_set]
    return added, removed


def key_for_question(question: Dict[str, Any]) -> str:
    section_key = question.get("section_key")
    if isinstance(section_key, str) and section_key:
        return section_key
    q = question.get("question")
    return str(q) if q else ""


def normalize_questions(questions: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    for entry in questions:
        if not isinstance(entry, dict):
            continue
        key = key_for_question(entry)
        if not key:
            continue
        out[key] = entry
    return out


def build_diff(
    left: List[Dict[str, Any]], right: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    left_map = normalize_questions(left)
    right_map = normalize_questions(right)
    ordered_keys = []
    for entry in right:
        key = key_for_question(entry)
        if key and key not in ordered_keys:
            ordered_keys.append(key)
    for entry in left:
        key = key_for_question(entry)
        if key and key not in ordered_keys:
            ordered_keys.append(key)
    diff: List[Dict[str, Any]] = []
    for key in ordered_keys:
        left_entry = left_map.get(key, {})
        right_entry = right_map.get(key, {})
        left_items = list(left_entry.get("items", []) or [])
        right_items = list(right_entry.get("items", []) or [])
        added, removed = diff_items(left_items, right_items)
        diff.append(
            {
                "question": right_entry.get("question")
                or left_entry.get("question")
                or key,
                "section_key": key,
                "added": added,
                "removed": removed,
                "left_count": len(left_items),
                "right_count": len(right_items),
            }
        )
    return diff


def write_markdown(path: str, left_path: str, right_path: str, diff: List[Dict[str, Any]]) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Status FAQ diff\n\n")
        f.write(f"- left: `{left_path}`\n")
        f.write(f"- right: `{right_path}`\n")
        f.write(f"- generated_at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        for entry in diff:
            f.write(f"## {entry.get('question','-')}\n\n")
            f.write(f"- left_count: {entry.get('left_count', 0)}\n")
            f.write(f"- right_count: {entry.get('right_count', 0)}\n\n")
            f.write("Added:\n\n")
            added = entry.get("added", [])
            if added:
                for item in added:
                    f.write(f"- {item}\n")
            else:
                f.write("- (none)\n")
            f.write("\nRemoved:\n\n")
            removed = entry.get("removed", [])
            if removed:
                for item in removed:
                    f.write(f"- {item}\n")
            else:
                f.write("- (none)\n")
            f.write("\n")


def write_json(path: str, left_path: str, right_path: str, diff: List[Dict[str, Any]]) -> None:
    ensure_parent_dir(path)
    payload = {
        "left": left_path,
        "right": right_path,
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "questions": diff,
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, sort_keys=True)
        f.write("\n")


def main() -> int:
    args = parse_args()
    try:
        left_questions = load_questions(args.left)
    except Exception as exc:
        print(f"ERROR: failed to load left FAQ: {exc}", file=sys.stderr)
        return 2
    try:
        right_questions = load_questions(args.right)
    except Exception as exc:
        print(f"ERROR: failed to load right FAQ: {exc}", file=sys.stderr)
        return 2
    diff = build_diff(left_questions, right_questions)
    write_markdown(args.out_md, args.left, args.right, diff)
    write_json(args.out_json, args.left, args.right, diff)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
