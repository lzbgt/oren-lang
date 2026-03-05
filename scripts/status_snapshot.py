#!/usr/bin/env python3
import argparse
import json
import os
import sys
from datetime import datetime
from typing import Dict, List, Tuple


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


def load_lines(path: str) -> List[str]:
    if not os.path.exists(path):
        return []
    with open(path, "r", encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


def is_heading(line: str) -> bool:
    return line.startswith("#") and line.lstrip().startswith("#")


def heading_text(line: str) -> str:
    return line.lstrip("# ").strip().lower()


def collect_section(lines: List[str], header_match: str) -> Tuple[str, List[str]]:
    current_title = ""
    collecting = False
    items: List[str] = []
    for line in lines:
        if is_heading(line):
            title = heading_text(line)
            if header_match in title:
                collecting = True
                current_title = line.strip().lstrip("#").strip()
                continue
            if collecting:
                break
        if collecting:
            striped = line.strip()
            if striped.startswith("- "):
                items.append(striped[2:])
    return current_title, items


def snapshot(lines: List[str]) -> Dict[str, Dict[str, List[str]]]:
    sections = {
        "production_readiness_gap": "production readiness gap",
        "backend_readiness": "backend readiness",
        "feature_readiness_gaps": "feature readiness gaps",
    }
    payload: Dict[str, Dict[str, List[str]]] = {}
    for key, match in sections.items():
        title, items = collect_section(lines, match)
        payload[key] = {
            "title": title or match,
            "items": items,
        }
    return payload


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
    lines = load_lines(args.status)
    if not lines:
        print(f"ERROR: status file not found or empty: {args.status}", file=sys.stderr)
        return 2
    payload = snapshot(lines)
    write_markdown(args.out_md, args.status, payload)
    write_json(args.out_json, args.status, payload)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
