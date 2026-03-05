#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
from typing import Any, Dict, List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sanitize readiness report markdown + JSON for sharing."
    )
    parser.add_argument(
        "--report",
        required=True,
        help="Input readiness report markdown path",
    )
    parser.add_argument(
        "--json",
        default="",
        help="Input readiness report JSON path (optional)",
    )
    parser.add_argument(
        "--out-md",
        default="build/reports/readiness_report_sanitized.md",
        help="Output sanitized markdown path",
    )
    parser.add_argument(
        "--out-json",
        default="build/reports/readiness_report_sanitized.json",
        help="Output sanitized JSON path",
    )
    parser.add_argument(
        "--keep-paths",
        action="store_true",
        help="Do not redact paths",
    )
    parser.add_argument(
        "--keep-git",
        action="store_true",
        help="Do not redact git metadata",
    )
    parser.add_argument(
        "--keep-env",
        action="store_true",
        help="Do not redact environment block",
    )
    return parser.parse_args()


def ensure_parent_dir(path: str) -> None:
    dir_name = os.path.dirname(path)
    if dir_name:
        os.makedirs(dir_name, exist_ok=True)


def redact_path(value: str) -> str:
    if not value:
        return value
    return "<redacted>"


def sanitize_markdown(lines: List[str], keep_paths: bool, keep_git: bool, keep_env: bool) -> List[str]:
    out: List[str] = []
    in_env_block = False
    in_workspace_diff = False
    for line in lines:
        if line.strip() == "## Environment (OREN_*)":
            if keep_env:
                out.append(line)
                in_env_block = True
            else:
                in_env_block = True
            continue
        if in_env_block:
            if keep_env:
                out.append(line)
            if line.strip() == "```":
                if keep_env:
                    # keep block; exit when closing
                    if out and out[-1].strip() == "```" and len(out) >= 2 and out[-2].strip() == "```":
                        in_env_block = False
                else:
                    # skip until closing
                    in_env_block = False
            if not keep_env and line.strip() == "```":
                in_env_block = False
            if not keep_env:
                continue
        if line.strip() == "## Workspace diff":
            in_workspace_diff = True
            continue
        if in_workspace_diff:
            if line.strip() == "```":
                # skip diff block entirely
                in_workspace_diff = False
            continue
        if line.startswith("- git: ") and not keep_git:
            out.append("- git: <redacted>")
            continue
        if line.startswith("- logs: ") and not keep_paths:
            out.append("- logs: <redacted>")
            continue
        if line.startswith("- json: ") and not keep_paths:
            out.append("- json: <redacted>")
            continue
        if line.startswith("- index: ") and not keep_paths:
            out.append("- index: <redacted>")
            continue
        if line.startswith("- status_") and not keep_paths and ":" in line:
            prefix = line.split(":", 1)[0]
            out.append(f"{prefix}: <redacted>")
            continue
        if line.strip().startswith("- log: `") and not keep_paths:
            out.append("  - log: `<redacted>`")
            continue
        if line.strip().startswith("- cmd: `"):
            out.append(line)
            continue
        out.append(line)
    return out


def sanitize_json(data: Dict[str, Any], keep_paths: bool, keep_git: bool, keep_env: bool) -> Dict[str, Any]:
    out = json.loads(json.dumps(data))
    if not keep_git and "git" in out:
        out["git"]["rev"] = "<redacted>"
        out["git"]["status"] = []
        out["git"]["diff_stat"] = ""
    if not keep_paths and "paths" in out:
        for key in list(out["paths"].keys()):
            out["paths"][key] = "<redacted>"
    if not keep_paths and "steps" in out:
        for step in out["steps"]:
            if isinstance(step, dict) and "log" in step:
                step["log"] = "<redacted>"
    if not keep_env and "env" in out:
        out["env"] = []
    return out


def main() -> int:
    args = parse_args()
    if not os.path.exists(args.report):
        print(f"ERROR: report not found: {args.report}", file=sys.stderr)
        return 2
    with open(args.report, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    sanitized = sanitize_markdown(lines, args.keep_paths, args.keep_git, args.keep_env)
    ensure_parent_dir(args.out_md)
    with open(args.out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(sanitized))
        f.write("\n")

    if args.json:
        if not os.path.exists(args.json):
            print(f"ERROR: json not found: {args.json}", file=sys.stderr)
            return 2
        with open(args.json, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            print("ERROR: json is not an object", file=sys.stderr)
            return 2
        out_json = sanitize_json(data, args.keep_paths, args.keep_git, args.keep_env)
        ensure_parent_dir(args.out_json)
        with open(args.out_json, "w", encoding="utf-8") as f:
            json.dump(out_json, f, indent=2, sort_keys=True)
            f.write("\n")
    print(f"OK: wrote {args.out_md}" + (f" and {args.out_json}" if args.json else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
