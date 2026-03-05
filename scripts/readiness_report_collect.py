#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import sys
from typing import Any, Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect readiness report artifacts into a snapshot directory."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--out-dir",
        default="build/reports/readiness_collect",
        help="Output directory for snapshots",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=5,
        help="Collect last N entries (default: 5)",
    )
    parser.add_argument(
        "--include-dry-run",
        action="store_true",
        help="Include dry_run entries",
    )
    parser.add_argument(
        "--copy-logs",
        action="store_true",
        help="Copy log_dir contents into snapshot",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing snapshot directories",
    )
    return parser.parse_args()


def parse_jsonl(path: str) -> List[Dict[str, Any]]:
    entries: List[Dict[str, Any]] = []
    if not os.path.exists(path):
        return entries
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(entry, dict):
                entries.append(entry)
    return entries


def ensure_dir(path: str) -> None:
    if path:
        os.makedirs(path, exist_ok=True)


def copy_file(src: str, dst: str) -> None:
    if not src or not os.path.exists(src):
        return
    ensure_dir(os.path.dirname(dst))
    shutil.copy2(src, dst)


def copy_dir(src: str, dst: str) -> None:
    if not src or not os.path.exists(src):
        return
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def snapshot_name(entry: Dict[str, Any]) -> str:
    ts = entry.get("timestamp", "unknown")
    profile = entry.get("profile", "unknown")
    tag = entry.get("tag", "")
    suffix = f"_{tag}" if tag else ""
    return f"{ts}_{profile}{suffix}"


def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
    if not args.include_dry_run:
        entries = [e for e in entries if e.get("dry_run") is not True]
    if args.limit and args.limit > 0:
        entries = entries[-args.limit :]

    ensure_dir(args.out_dir)
    collected: List[Dict[str, Any]] = []
    for entry in entries:
        name = snapshot_name(entry)
        snapshot_dir = os.path.join(args.out_dir, name)
        if os.path.exists(snapshot_dir) and not args.overwrite:
            continue
        if os.path.exists(snapshot_dir) and args.overwrite:
            shutil.rmtree(snapshot_dir)
        ensure_dir(snapshot_dir)

        report = str(entry.get("report", ""))
        report_json = str(entry.get("json", ""))
        status_md = str(entry.get("status_snapshot_md", ""))
        status_json = str(entry.get("status_snapshot_json", ""))
        status_faq_md = str(entry.get("status_faq_md", ""))
        status_faq_json = str(entry.get("status_faq_json", ""))
        status_matrix_md = str(entry.get("status_matrix_md", ""))
        status_matrix_json = str(entry.get("status_matrix_json", ""))
        status_overview_md = str(entry.get("status_overview_md", ""))
        log_dir = str(entry.get("log_dir", ""))

        copy_file(report, os.path.join(snapshot_dir, "readiness_report.md"))
        copy_file(report_json, os.path.join(snapshot_dir, "readiness_report.json"))
        if status_md:
            copy_file(status_md, os.path.join(snapshot_dir, "status_snapshot.md"))
        if status_json:
            copy_file(status_json, os.path.join(snapshot_dir, "status_snapshot.json"))
        if status_faq_md:
            copy_file(status_faq_md, os.path.join(snapshot_dir, "status_faq.md"))
        if status_faq_json:
            copy_file(status_faq_json, os.path.join(snapshot_dir, "status_faq.json"))
        if status_matrix_md:
            copy_file(status_matrix_md, os.path.join(snapshot_dir, "status_matrix.md"))
        if status_matrix_json:
            copy_file(status_matrix_json, os.path.join(snapshot_dir, "status_matrix.json"))
        if status_overview_md:
            copy_file(status_overview_md, os.path.join(snapshot_dir, "status_overview.md"))
        if args.copy_logs:
            copy_dir(log_dir, os.path.join(snapshot_dir, "logs"))

        meta = {
            "timestamp": entry.get("timestamp", ""),
            "profile": entry.get("profile", ""),
            "tag": entry.get("tag", ""),
            "overall": entry.get("overall", ""),
            "report": report,
            "json": report_json,
            "status_snapshot_md": status_md,
            "status_snapshot_json": status_json,
            "status_faq_md": status_faq_md,
            "status_faq_json": status_faq_json,
            "status_matrix_md": status_matrix_md,
            "status_matrix_json": status_matrix_json,
            "status_overview_md": status_overview_md,
            "log_dir": log_dir,
        }
        with open(os.path.join(snapshot_dir, "snapshot.json"), "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2, sort_keys=True)
            f.write("\n")
        collected.append(meta)

    summary_path = os.path.join(args.out_dir, "index.json")
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump({"total": len(collected), "entries": collected}, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"OK: collected {len(collected)} snapshots in {args.out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
