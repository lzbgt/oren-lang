#!/usr/bin/env python3
import argparse
import json
import os
import sys
from datetime import datetime
from typing import Any, Dict, List

from status_matrix_lib import matrix_from_sections
from status_snapshot_lib import snapshot_from_status


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a readiness matrix from STATUS.md sections."
    )
    parser.add_argument(
        "--status",
        default="docs/STATUS.md",
        help="Path to STATUS.md",
    )
    parser.add_argument(
        "--out-md",
        default="build/reports/status_matrix.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/status_matrix.json",
        help="Output JSON path",
    )
    return parser.parse_args()


def ensure_parent_dir(path: str) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)


def escape_table(text: str) -> str:
    if not text:
        return ""
    return text.replace("|", "\\|").replace("\n", "<br>")


def write_table(
    f,
    title: str,
    name_label: str,
    rows: List[Dict[str, str]],
) -> None:
    f.write(f"## {title}\n\n")
    if not rows:
        f.write("- (no items found)\n\n")
        return
    f.write(f"| {name_label} | Notes |\n")
    f.write("| --- | --- |\n")
    for row in rows:
        name = escape_table(row.get("name", ""))
        notes = escape_table(row.get("notes", "")) or escape_table(row.get("raw", ""))
        f.write(f"| {name} | {notes} |\n")
    f.write("\n")


def write_markdown(
    path: str,
    status_path: str,
    sections: Dict[str, Dict[str, Any]],
) -> None:
    ensure_parent_dir(path)
    generated_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Status readiness matrix\n\n")
        f.write(f"- source: `{status_path}`\n")
        f.write(f"- generated_at: {generated_at}\n\n")
        matrix = matrix_from_sections(sections)
        gap_rows = matrix.get("production_readiness_gap", [])
        backend_rows = matrix.get("backend_readiness", [])
        feature_rows = matrix.get("feature_readiness_gaps", [])
        write_table(
            f,
            sections.get("production_readiness_gap", {}).get("title", "Production readiness gap"),
            "Gap",
            gap_rows,
        )
        write_table(
            f,
            sections.get("backend_readiness", {}).get("title", "Backend readiness"),
            "Backend",
            backend_rows,
        )
        write_table(
            f,
            sections.get("feature_readiness_gaps", {}).get("title", "Feature readiness gaps"),
            "Feature",
            feature_rows,
        )


def write_json(
    path: str,
    status_path: str,
    sections: Dict[str, Dict[str, Any]],
) -> None:
    ensure_parent_dir(path)
    out = {
        "source": status_path,
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "sections": matrix_from_sections(sections),
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, sort_keys=True)
        f.write("\n")


def main() -> int:
    args = parse_args()
    if not os.path.exists(args.status):
        print(f"ERROR: status file not found or empty: {args.status}", file=sys.stderr)
        return 2
    sections = snapshot_from_status(args.status)
    write_markdown(args.out_md, args.status, sections)
    write_json(args.out_json, args.status, sections)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
