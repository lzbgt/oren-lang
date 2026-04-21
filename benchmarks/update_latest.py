#!/usr/bin/env python3
import argparse
import json
import re
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULTS_DIR = ROOT / "build" / "benchmarks" / "results"
LATEST_PATH = ROOT / "benchmarks" / "RESULTS_LATEST.md"


def _parse_timestamp(value):
    for fmt in ("%Y%m%d_%H%M%S", "%Y%m%d_%H%M%S_%f"):
        try:
            return datetime.strptime(value, fmt)
        except Exception:
            pass
    return None


def _load_result(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    meta = data.get("meta", {})
    results = data.get("results", {})
    program = meta.get("program")
    if not program:
        raise RuntimeError(f"missing program in {path}")
    ts = _parse_timestamp(meta.get("timestamp", ""))
    return {
        "path": path,
        "program": program,
        "timestamp": ts,
        "meta": meta,
        "results": results,
    }


def _collect_latest_per_program():
    latest = {}
    for path in RESULTS_DIR.glob("*.json"):
        try:
            item = _load_result(path)
        except Exception:
            continue
        program = item["program"]
        prev = latest.get(program)
        if prev is None or (item["timestamp"] and item["timestamp"] > prev["timestamp"]):
            latest[program] = item
    return list(latest.values())


def _select_results(paths, programs):
    items = []
    if paths:
        for path in paths:
            item = _load_result(Path(path))
            items.append(item)
    else:
        items = _collect_latest_per_program()
    if programs:
        allow = set(programs)
        items = [item for item in items if item["program"] in allow]
    items.sort(key=lambda it: it["program"])
    return items


def _format_ratio(value, baseline):
    if baseline is None or baseline == 0 or value is None:
        return "n/a"
    return f"{value / baseline:.2f}×"


def _build_table(items):
    lines = []
    lines.append("| benchmark | C median (s) | Oren C median (x) | Oren native median (x) | Oren OBC median (x) |")
    lines.append("| --- | --- | --- | --- | --- |")
    for item in items:
        results = item["results"]
        c = results.get("c", {})
        c_median = c.get("median_s")
        if c_median is None:
            raise RuntimeError(f"missing C results for {item['program']}")
        def fmt_variant(key):
            r = results.get(key)
            if not r:
                return "n/a"
            median = r.get("median_s")
            if median is None:
                return "n/a"
            ratio = _format_ratio(median, c_median)
            return f"{median:.6f} ({ratio})"
        lines.append(
            "| {program} | {c_median:.6f} | {oren_c} | {oren_native} | {oren_obc} |".format(
                program=item["program"],
                c_median=c_median,
                oren_c=fmt_variant("oren_c"),
                oren_native=fmt_variant("oren_native"),
                oren_obc=fmt_variant("oren_obc"),
            )
        )
    return lines


def _update_latest(items):
    if not LATEST_PATH.exists():
        raise RuntimeError(f"missing {LATEST_PATH}")
    text = LATEST_PATH.read_text(encoding="utf-8")
    lines = text.splitlines()

    latest_ts = None
    for item in items:
        if item["timestamp"] and (latest_ts is None or item["timestamp"] > latest_ts):
            latest_ts = item["timestamp"]

    date_line = None
    if latest_ts:
        date_line = f"**Date:** {latest_ts.strftime('%Y-%m-%d')}  "

    host_line = None
    if items:
        meta = items[0]["meta"]
        host = meta.get("host", "")
        cpu = meta.get("cpu_brand", "")
        cores = meta.get("cpu_cores", "")
        mem = meta.get("mem_bytes", "")
        host_parts = [p for p in [host, cpu] if p]
        host_str = ", ".join(host_parts)
        extras = []
        if cores:
            extras.append(f"{cores} cores")
        if mem:
            extras.append(f"{mem} bytes")
        if extras:
            host_str = f"{host_str} ({', '.join(extras)})" if host_str else ", ".join(extras)
        if host_str:
            host_line = f"**Host:** {host_str}"

    header_line = None
    if items:
        meta = items[0]["meta"]
        cpu = meta.get("cpu_brand", "")
        platform = meta.get("platform", "")
        machine = meta.get("machine", "")
        label_parts = [p for p in [cpu, platform, machine] if p]
        if label_parts:
            header_line = f"# Latest Benchmark Snapshot ({', '.join(label_parts)})"

    table_lines = _build_table(items)

    out = []
    in_table = False
    table_replaced = False
    i = 0
    while i < len(lines):
        line = lines[i]
        if header_line and line.startswith("# Latest Benchmark Snapshot"):
            out.append(header_line)
            i += 1
            continue
        if date_line and line.startswith("**Date:**"):
            out.append(date_line)
            i += 1
            continue
        if host_line and line.startswith("**Host:**"):
            out.append(host_line)
            i += 1
            continue
        if line.startswith("| benchmark |"):
            out.extend(table_lines)
            table_replaced = True
            in_table = True
            i += 1
            while i < len(lines) and lines[i].startswith("|"):
                i += 1
            continue
        if in_table and line.strip() == "":
            in_table = False
        if not in_table:
            out.append(line)
        i += 1

    if not table_replaced:
        out.append("")
        out.extend(table_lines)

    LATEST_PATH.write_text("\n".join(out) + "\n", encoding="utf-8")


def _prune_results(keep_paths):
    keep = {path.resolve() for path in keep_paths}
    for path in RESULTS_DIR.glob("*.md"):
        if path.resolve() not in keep:
            path.unlink()
    for path in RESULTS_DIR.glob("*.json"):
        if path.resolve() not in keep:
            path.unlink()


def main():
    parser = argparse.ArgumentParser(description="Update benchmarks/RESULTS_LATEST.md from result JSON files.")
    parser.add_argument("results", nargs="*", help="Result JSON files (defaults to latest per program).")
    parser.add_argument("--programs", help="Comma/space-separated program list (filter).")
    parser.add_argument("--prune", action="store_true", help="Delete unreferenced result files after update.")
    args = parser.parse_args()

    programs = None
    if args.programs:
        programs = [p for p in re.split(r"[\s,]+", args.programs.strip()) if p]

    items = _select_results(args.results, programs)
    if not items:
        raise RuntimeError("no benchmark results found")

    _update_latest(items)

    if args.prune:
        keep = []
        for item in items:
            keep.append(item["path"].with_suffix(".md"))
            keep.append(item["path"])
        _prune_results(keep)


if __name__ == "__main__":
    main()
