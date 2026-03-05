#!/usr/bin/env python3
import argparse
import json
import os
import sys
from typing import Any, Dict, List

from status_item_format import format_multiline_item


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render status FAQ/snapshot/matrix JSON into markdown."
    )
    parser.add_argument("--faq-json", default="", help="Status FAQ JSON path (optional)")
    parser.add_argument("--snapshot-json", default="", help="Status snapshot JSON path (optional)")
    parser.add_argument("--matrix-json", default="", help="Status matrix JSON path (optional)")
    parser.add_argument(
        "--max-items",
        type=int,
        default=10,
        help="Max items per section (default: 10; <=0 means no limit).",
    )
    parser.add_argument(
        "--title",
        default="Status Overview",
        help="Top-level markdown title.",
    )
    parser.add_argument(
        "--out-md",
        default="build/reports/status_overview.md",
        help="Output markdown path ('-' for stdout).",
    )
    return parser.parse_args()


def read_json(path: str) -> Dict[str, Any]:
    if not path or not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, dict) else {}


def normalize_structured_items(value: Any) -> List[str]:
    if isinstance(value, list):
        items = []
        for entry in value:
            if not isinstance(entry, dict):
                continue
            lines = entry.get("lines")
            if isinstance(lines, list) and lines:
                items.append("\n".join(str(line) for line in lines))
                continue
            raw = entry.get("raw")
            if isinstance(raw, str) and raw:
                items.append(raw)
                continue
            head = entry.get("head")
            if isinstance(head, str) and head:
                items.append(head)
        return items
    return []


def render_items_md(items: List[str], max_items: int) -> List[str]:
    if not items:
        return ["- (no items)"]
    if max_items <= 0:
        max_items = len(items)
    lines: List[str] = []
    for item in items[:max_items]:
        for line in format_multiline_item(item):
            lines.append(line)
    if len(items) > max_items:
        lines.append(f"- (truncated, {len(items)} total)")
    return lines


def render_status_faq_md(data: Dict[str, Any], max_items: int) -> str:
    questions = data.get("questions")
    if not isinstance(questions, list) or not questions:
        return ""
    out: List[str] = ["## Status FAQ", ""]
    for entry in questions:
        if not isinstance(entry, dict):
            continue
        question = str(entry.get("question", "-"))
        out.append(f"### {question}")
        items = normalize_structured_items(entry.get("items_structured"))
        if not items:
            raw_items = entry.get("items")
            if isinstance(raw_items, list):
                items = [str(item) for item in raw_items]
        out.extend(render_items_md(items, max_items))
        out.append("")
    return "\n".join(out).rstrip()


def render_status_snapshot_md(data: Dict[str, Any], max_items: int) -> str:
    sections = data.get("sections")
    if not isinstance(sections, dict) or not sections:
        return ""
    order = ("production_readiness_gap", "backend_readiness", "feature_readiness_gaps")
    out: List[str] = ["## Status Snapshot", ""]
    for key in order:
        section = sections.get(key)
        if not isinstance(section, dict):
            continue
        title = str(section.get("title") or key)
        out.append(f"### {title}")
        items = normalize_structured_items(section.get("items_structured"))
        if not items:
            raw_items = section.get("items")
            if isinstance(raw_items, list):
                items = [str(item) for item in raw_items]
        out.extend(render_items_md(items, max_items))
        out.append("")
    return "\n".join(out).rstrip()


def render_status_matrix_md(data: Dict[str, Any], max_items: int) -> str:
    sections = data.get("sections") if isinstance(data.get("sections"), dict) else data
    if not isinstance(sections, dict) or not sections:
        return ""
    order = ("production_readiness_gap", "backend_readiness", "feature_readiness_gaps")
    title_map = {
        "production_readiness_gap": "Production readiness gap",
        "backend_readiness": "Backend readiness",
        "feature_readiness_gaps": "Feature readiness gaps",
    }
    out: List[str] = ["## Status Matrix", ""]
    for key in order:
        rows = sections.get(key, [])
        if not isinstance(rows, list) or not rows:
            continue
        out.append(f"### {title_map.get(key, key)}")
        items: List[str] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            name = str(row.get("name", "-"))
            notes_lines = row.get("notes_lines")
            notes = ""
            if isinstance(notes_lines, list) and notes_lines:
                notes = "\n".join(str(line) for line in notes_lines)
            elif isinstance(row.get("notes"), str):
                notes = row.get("notes", "")
            elif isinstance(row.get("raw"), str):
                notes = row.get("raw", "")
            item = f"{name}: {notes}" if notes else name
            items.append(item)
        out.extend(render_items_md(items, max_items))
        out.append("")
    return "\n".join(out).rstrip()


def render_overview(
    title: str,
    faq: Dict[str, Any],
    snapshot: Dict[str, Any],
    matrix: Dict[str, Any],
    max_items: int,
) -> str:
    sections = [
        render_status_faq_md(faq, max_items),
        render_status_snapshot_md(snapshot, max_items),
        render_status_matrix_md(matrix, max_items),
    ]
    body = "\n\n".join(section for section in sections if section)
    if not body:
        body = "(no data)"
    return f"# {title}\n\n{body}\n"


def resolve_default(path: str, fallback: str) -> str:
    if path:
        return path
    return fallback if os.path.exists(fallback) else ""


def main() -> int:
    args = parse_args()
    faq_path = resolve_default(args.faq_json, "build/reports/status_faq.json")
    snapshot_path = resolve_default(args.snapshot_json, "build/reports/status_snapshot.json")
    matrix_path = resolve_default(args.matrix_json, "build/reports/status_matrix.json")
    if not any([faq_path, snapshot_path, matrix_path]):
        print("ERROR: no status JSON paths provided or found.", file=sys.stderr)
        return 2
    faq = read_json(faq_path)
    snapshot = read_json(snapshot_path)
    matrix = read_json(matrix_path)
    rendered = render_overview(args.title, faq, snapshot, matrix, args.max_items)
    if args.out_md == "-" or args.out_md == "":
        sys.stdout.write(rendered)
        return 0
    os.makedirs(os.path.dirname(args.out_md), exist_ok=True)
    with open(args.out_md, "w", encoding="utf-8") as f:
        f.write(rendered)
    print(f"OK: wrote {args.out_md}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
