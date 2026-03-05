#!/usr/bin/env python3
import argparse
import csv
import json
import os
import sys
from typing import Any, Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit readiness_index.jsonl for missing referenced files."
    )
    parser.add_argument(
        "--index",
        default="build/reports/readiness_index.jsonl",
        help="Path to readiness_index.jsonl",
    )
    parser.add_argument(
        "--out-md",
        default="build/reports/readiness_index_audit.md",
        help="Output markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/readiness_index_audit.json",
        help="Output JSON path",
    )
    parser.add_argument(
        "--out-csv",
        default="",
        help="Output CSV path (optional)",
    )
    parser.add_argument(
        "--out-samples-csv",
        default="",
        help="Output CSV for missing samples (optional)",
    )
    parser.add_argument(
        "--allow-missing",
        action="store_true",
        help="Do not fail on missing files; report only",
    )
    parser.add_argument(
        "--max-missing",
        type=int,
        default=-1,
        help="Fail if missing_any exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-report",
        type=int,
        default=-1,
        help="Fail if missing report exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-json",
        type=int,
        default=-1,
        help="Fail if missing json exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-log-dir",
        type=int,
        default=-1,
        help="Fail if missing log_dir exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-status-snapshot-md",
        type=int,
        default=-1,
        help="Fail if missing status_snapshot_md exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-status-snapshot-json",
        type=int,
        default=-1,
        help="Fail if missing status_snapshot_json exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-status-faq-md",
        type=int,
        default=-1,
        help="Fail if missing status_faq_md exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-status-faq-json",
        type=int,
        default=-1,
        help="Fail if missing status_faq_json exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-status-matrix-md",
        type=int,
        default=-1,
        help="Fail if missing status_matrix_md exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-status-matrix-json",
        type=int,
        default=-1,
        help="Fail if missing status_matrix_json exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--max-missing-status-overview-md",
        type=int,
        default=-1,
        help="Fail if missing status_overview_md exceeds this count (disabled if <0)",
    )
    parser.add_argument(
        "--include-dry-run",
        action="store_true",
        help="Include dry_run entries in audit (default: skip)",
    )
    parser.add_argument(
        "--sample",
        type=int,
        default=20,
        help="Max missing samples to include in report",
    )
    return parser.parse_args()


def ensure_parent_dir(path: str) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)


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


def file_exists(path: str) -> bool:
    if not path:
        return False
    return os.path.exists(path)


def audit_entries(entries: List[Dict[str, Any]], include_dry_run: bool, sample: int) -> Dict[str, Any]:
    missing_report = 0
    missing_json = 0
    missing_log_dir = 0
    missing_status_snapshot_md = 0
    missing_status_snapshot_json = 0
    missing_status_faq_md = 0
    missing_status_faq_json = 0
    missing_status_matrix_md = 0
    missing_status_matrix_json = 0
    missing_status_overview_md = 0
    missing_any = 0
    samples: List[Dict[str, Any]] = []
    checked = 0

    for entry in entries:
        if not include_dry_run and entry.get("dry_run") is True:
            continue
        checked += 1
        report_path = str(entry.get("report", ""))
        json_path = str(entry.get("json", ""))
        log_dir = str(entry.get("log_dir", ""))
        status_snapshot_md = str(entry.get("status_snapshot_md", ""))
        status_snapshot_json = str(entry.get("status_snapshot_json", ""))
        status_faq_md = str(entry.get("status_faq_md", ""))
        status_faq_json = str(entry.get("status_faq_json", ""))
        status_matrix_md = str(entry.get("status_matrix_md", ""))
        status_matrix_json = str(entry.get("status_matrix_json", ""))
        status_overview_md = str(entry.get("status_overview_md", ""))
        report_ok = file_exists(report_path)
        json_ok = file_exists(json_path)
        log_ok = file_exists(log_dir)
        status_snapshot_md_ok = not status_snapshot_md or file_exists(status_snapshot_md)
        status_snapshot_json_ok = not status_snapshot_json or file_exists(status_snapshot_json)
        status_faq_md_ok = not status_faq_md or file_exists(status_faq_md)
        status_faq_json_ok = not status_faq_json or file_exists(status_faq_json)
        status_matrix_md_ok = not status_matrix_md or file_exists(status_matrix_md)
        status_matrix_json_ok = not status_matrix_json or file_exists(status_matrix_json)
        status_overview_md_ok = not status_overview_md or file_exists(status_overview_md)
        missing = []
        if not report_ok:
            missing_report += 1
            missing.append("report")
        if not json_ok:
            missing_json += 1
            missing.append("json")
        if not log_ok:
            missing_log_dir += 1
            missing.append("log_dir")
        if not status_snapshot_md_ok:
            missing_status_snapshot_md += 1
            missing.append("status_snapshot_md")
        if not status_snapshot_json_ok:
            missing_status_snapshot_json += 1
            missing.append("status_snapshot_json")
        if not status_faq_md_ok:
            missing_status_faq_md += 1
            missing.append("status_faq_md")
        if not status_faq_json_ok:
            missing_status_faq_json += 1
            missing.append("status_faq_json")
        if not status_matrix_md_ok:
            missing_status_matrix_md += 1
            missing.append("status_matrix_md")
        if not status_matrix_json_ok:
            missing_status_matrix_json += 1
            missing.append("status_matrix_json")
        if not status_overview_md_ok:
            missing_status_overview_md += 1
            missing.append("status_overview_md")
        if missing:
            missing_any += 1
            if len(samples) < sample:
                samples.append(
                    {
                        "timestamp": entry.get("timestamp", ""),
                        "profile": entry.get("profile", ""),
                        "tag": entry.get("tag", ""),
                        "missing": missing,
                        "report": report_path,
                        "json": json_path,
                        "log_dir": log_dir,
                        "status_snapshot_md": status_snapshot_md,
                        "status_snapshot_json": status_snapshot_json,
                        "status_faq_md": status_faq_md,
                        "status_faq_json": status_faq_json,
                        "status_matrix_md": status_matrix_md,
                        "status_matrix_json": status_matrix_json,
                        "status_overview_md": status_overview_md,
                    }
                )

    return {
        "checked": checked,
        "missing_report": missing_report,
        "missing_json": missing_json,
        "missing_log_dir": missing_log_dir,
        "missing_status_snapshot_md": missing_status_snapshot_md,
        "missing_status_snapshot_json": missing_status_snapshot_json,
        "missing_status_faq_md": missing_status_faq_md,
        "missing_status_faq_json": missing_status_faq_json,
        "missing_status_matrix_md": missing_status_matrix_md,
        "missing_status_matrix_json": missing_status_matrix_json,
        "missing_status_overview_md": missing_status_overview_md,
        "missing_any": missing_any,
        "samples": samples,
    }


def write_markdown(path: str, summary: Dict[str, Any]) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Readiness index audit\n\n")
        f.write(f"- checked entries: {summary['checked']}\n")
        f.write(f"- missing report: {summary['missing_report']}\n")
        f.write(f"- missing json: {summary['missing_json']}\n")
        f.write(f"- missing log_dir: {summary['missing_log_dir']}\n")
        f.write(f"- missing status_snapshot_md: {summary['missing_status_snapshot_md']}\n")
        f.write(f"- missing status_snapshot_json: {summary['missing_status_snapshot_json']}\n")
        f.write(f"- missing status_faq_md: {summary['missing_status_faq_md']}\n")
        f.write(f"- missing status_faq_json: {summary['missing_status_faq_json']}\n")
        f.write(f"- missing status_matrix_md: {summary['missing_status_matrix_md']}\n")
        f.write(f"- missing status_matrix_json: {summary['missing_status_matrix_json']}\n")
        f.write(f"- missing status_overview_md: {summary['missing_status_overview_md']}\n")
        f.write(f"- missing any: {summary['missing_any']}\n\n")
        f.write("## Samples\n\n")
        if not summary["samples"]:
            f.write("- none\n")
            return
        for sample in summary["samples"]:
            f.write(f"- {sample.get('timestamp','-')} {sample.get('profile','-')} {sample.get('tag','-')} missing={sample.get('missing',[])}\n")


def write_json(path: str, summary: Dict[str, Any]) -> None:
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, sort_keys=True)
        f.write("\n")


def write_csv(path: str, summary: Dict[str, Any]) -> None:
    if not path:
        return
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "checked",
                "missing_any",
                "missing_report",
                "missing_json",
                "missing_log_dir",
                "missing_status_snapshot_md",
                "missing_status_snapshot_json",
                "missing_status_faq_md",
                "missing_status_faq_json",
                "missing_status_matrix_md",
                "missing_status_matrix_json",
                "missing_status_overview_md",
            ],
        )
        writer.writeheader()
        writer.writerow(
            {
                "checked": summary.get("checked", 0),
                "missing_any": summary.get("missing_any", 0),
                "missing_report": summary.get("missing_report", 0),
                "missing_json": summary.get("missing_json", 0),
                "missing_log_dir": summary.get("missing_log_dir", 0),
                "missing_status_snapshot_md": summary.get("missing_status_snapshot_md", 0),
                "missing_status_snapshot_json": summary.get("missing_status_snapshot_json", 0),
                "missing_status_faq_md": summary.get("missing_status_faq_md", 0),
                "missing_status_faq_json": summary.get("missing_status_faq_json", 0),
                "missing_status_matrix_md": summary.get("missing_status_matrix_md", 0),
                "missing_status_matrix_json": summary.get("missing_status_matrix_json", 0),
                "missing_status_overview_md": summary.get("missing_status_overview_md", 0),
            }
        )


def write_samples_csv(path: str, summary: Dict[str, Any]) -> None:
    if not path:
        return
    ensure_parent_dir(path)
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "timestamp",
                "profile",
                "tag",
                "missing",
                "report",
                "json",
                "log_dir",
                "status_snapshot_md",
                "status_snapshot_json",
                "status_faq_md",
                "status_faq_json",
                "status_matrix_md",
                "status_matrix_json",
                "status_overview_md",
            ],
        )
        writer.writeheader()
        for sample in summary.get("samples", []):
            missing = sample.get("missing", [])
            if isinstance(missing, list):
                missing = ",".join(missing)
            writer.writerow(
                {
                    "timestamp": sample.get("timestamp", ""),
                    "profile": sample.get("profile", ""),
                    "tag": sample.get("tag", ""),
                    "missing": missing,
                    "report": sample.get("report", ""),
                    "json": sample.get("json", ""),
                    "log_dir": sample.get("log_dir", ""),
                    "status_snapshot_md": sample.get("status_snapshot_md", ""),
                    "status_snapshot_json": sample.get("status_snapshot_json", ""),
                    "status_faq_md": sample.get("status_faq_md", ""),
                    "status_faq_json": sample.get("status_faq_json", ""),
                    "status_matrix_md": sample.get("status_matrix_md", ""),
                    "status_matrix_json": sample.get("status_matrix_json", ""),
                    "status_overview_md": sample.get("status_overview_md", ""),
                }
            )

def main() -> int:
    args = parse_args()
    entries = parse_jsonl(args.index)
    if not entries:
        print(f"WARN: no entries found in {args.index}", file=sys.stderr)
    summary = audit_entries(entries, args.include_dry_run, args.sample)
    write_markdown(args.out_md, summary)
    write_json(args.out_json, summary)
    if args.out_csv:
        write_csv(args.out_csv, summary)
    if args.out_samples_csv:
        write_samples_csv(args.out_samples_csv, summary)
    print(f"OK: wrote {args.out_md} and {args.out_json}")
    if args.allow_missing:
        return 0
    if args.max_missing >= 0 and summary["missing_any"] > args.max_missing:
        print(f"FAIL: missing_any {summary['missing_any']} > {args.max_missing}", file=sys.stderr)
        return 2
    thresholds = {
        "report": args.max_missing_report,
        "json": args.max_missing_json,
        "log_dir": args.max_missing_log_dir,
        "status_snapshot_md": args.max_missing_status_snapshot_md,
        "status_snapshot_json": args.max_missing_status_snapshot_json,
        "status_faq_md": args.max_missing_status_faq_md,
        "status_faq_json": args.max_missing_status_faq_json,
        "status_matrix_md": args.max_missing_status_matrix_md,
        "status_matrix_json": args.max_missing_status_matrix_json,
        "status_overview_md": args.max_missing_status_overview_md,
    }
    for field, threshold in thresholds.items():
        if threshold >= 0 and summary.get(f"missing_{field}", 0) > threshold:
            print(
                f"FAIL: missing_{field} {summary.get(f'missing_{field}', 0)} > {threshold}",
                file=sys.stderr,
            )
            return 2
    if summary["missing_any"] > 0:
        print(f"FAIL: missing_any {summary['missing_any']}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
