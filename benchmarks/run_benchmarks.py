#!/usr/bin/env python3
import json
import os
import platform
import statistics
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOG_DIR = ROOT / "build" / "logs"
RESULTS_DIR = ROOT / "benchmarks" / "results"

DEFAULT_RUNS = 5
DEFAULT_WARMUPS = 1
DEFAULT_RSS = 0


def _run(cmd, env=None, log_path=None, time_path=None):
    start = time.perf_counter()
    if time_path:
        time_path.parent.mkdir(parents=True, exist_ok=True)
        if platform.system() == "Darwin":
            cmd = ["/usr/bin/time", "-l", "-o", str(time_path)] + cmd
        else:
            cmd = ["/usr/bin/time", "-v", "-o", str(time_path)] + cmd
    if log_path:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("w", encoding="utf-8") as f:
            proc = subprocess.run(cmd, cwd=ROOT, env=env, stdout=f, stderr=subprocess.STDOUT, text=True)
    else:
        proc = subprocess.run(cmd, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    dt = time.perf_counter() - start
    if proc.returncode != 0:
        if log_path:
            raise RuntimeError(f"command failed rc={proc.returncode}: {cmd} (see {log_path})")
        raise RuntimeError(f"command failed rc={proc.returncode}: {cmd}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}")
    return dt, proc.stdout if proc.stdout is not None else ""


def _parse_rss_bytes(time_path):
    if not time_path or not time_path.exists():
        return None
    data = time_path.read_text(encoding="utf-8", errors="replace")
    for line in data.splitlines():
        if "maximum resident set size" in line:
            # macOS time -l: bytes
            parts = line.strip().split()
            try:
                return int(parts[0])
            except Exception:
                return None
        if "Maximum resident set size" in line:
            # GNU time -v: kbytes
            parts = line.strip().split()
            if parts:
                try:
                    return int(parts[-1]) * 1024
                except Exception:
                    return None
    return None


def _time_cmd(cmd, runs, warmups, env=None, rss_enabled=False, rss_dir=None):
    for _ in range(warmups):
        _run(cmd, env=env)
    times = []
    rss = []
    out_sample = None
    for _ in range(runs):
        time_path = None
        if rss_enabled and rss_dir is not None:
            time_path = rss_dir / f"time_{len(times)}.log"
        dt, out = _run(cmd, env=env, time_path=time_path)
        times.append(dt)
        if rss_enabled:
            rss_bytes = _parse_rss_bytes(time_path)
            if rss_bytes is not None:
                rss.append(rss_bytes)
        if out_sample is None:
            out_sample = out.strip()
    return times, rss, out_sample


def _sysctl_value(key):
    try:
        out = subprocess.check_output(["sysctl", "-n", key], cwd=ROOT).decode("utf-8").strip()
        return out
    except Exception:
        return ""


def main():
    runs = int(os.environ.get("OREN_BENCH_RUNS", DEFAULT_RUNS))
    warmups = int(os.environ.get("OREN_BENCH_WARMUPS", DEFAULT_WARMUPS))
    rss_enabled = int(os.environ.get("OREN_BENCH_RSS", DEFAULT_RSS)) == 1
    program = os.environ.get("OREN_BENCH_PROGRAM", "loop_sum")

    bench_dir = ROOT / "benchmarks" / program
    if not bench_dir.exists():
        raise RuntimeError(f"unknown benchmark program: {program}")

    build_dir = ROOT / "build" / "benchmarks" / program

    build_dir.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")

    c_bin = build_dir / f"{program}_c"
    oren_c_bin = build_dir / f"{program}_oren_c"
    oren_native_bin = build_dir / f"{program}_oren_native"
    obc_out = build_dir / f"{program}.obc"

    avm_bin = ROOT / "avm"
    oren_bin = ROOT / "oren_stage2"

    _run(["cc", "-O2", "-o", str(c_bin), str(bench_dir / f"{program}.c")], log_path=LOG_DIR / f"bench_build_c_{program}_{ts}.log")
    _run([str(oren_bin), "build", str(bench_dir / f"{program}.oren"), "--backend", "c", "--no-debug", "-o", str(oren_c_bin)], log_path=LOG_DIR / f"bench_build_oren_c_{program}_{ts}.log")
    _run([str(oren_bin), "build", str(bench_dir / f"{program}.oren"), "--backend", "native", "--no-debug", "-o", str(oren_native_bin)], log_path=LOG_DIR / f"bench_build_oren_native_{program}_{ts}.log")
    _run([str(oren_bin), "build", str(bench_dir / f"{program}.oren"), "--backend", "bytecode", "-o", str(obc_out)], log_path=LOG_DIR / f"bench_build_oren_obc_{program}_{ts}.log")

    if not avm_bin.exists():
        _run(["make", "avm"], log_path=LOG_DIR / f"bench_build_avm_{ts}.log")

    results = {}
    outputs = {}
    rss_results = {}

    suites = [
        ("c", [str(c_bin)]),
        ("oren_c", [str(oren_c_bin)]),
        ("oren_native", [str(oren_native_bin)]),
        ("oren_obc", [str(avm_bin), str(obc_out)]),
    ]

    for name, cmd in suites:
        rss_dir = None
        if rss_enabled:
            rss_dir = LOG_DIR / f"bench_rss_{name}_{ts}"
        times, rss, out = _time_cmd(cmd, runs=runs, warmups=warmups, rss_enabled=rss_enabled, rss_dir=rss_dir)
        results[name] = {
            "runs": times,
            "median_s": statistics.median(times),
            "mean_s": statistics.mean(times),
            "min_s": min(times),
            "max_s": max(times),
        }
        if rss_enabled and rss:
            rss_results[name] = {
                "runs": rss,
                "median_bytes": int(statistics.median(rss)),
                "mean_bytes": int(statistics.mean(rss)),
                "min_bytes": min(rss),
                "max_bytes": max(rss),
            }
        outputs[name] = out

    # Output consistency check
    first_out = None
    for name, out in outputs.items():
        if first_out is None:
            first_out = out
        elif out != first_out:
            raise RuntimeError(f"benchmark output mismatch: {name} output={out!r} expected={first_out!r}")

    meta = {
        "timestamp": ts,
        "host": platform.node(),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "cpu_brand": _sysctl_value("machdep.cpu.brand_string"),
        "cpu_cores": _sysctl_value("hw.ncpu"),
        "mem_bytes": _sysctl_value("hw.memsize"),
        "git_rev": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode("utf-8").strip(),
        "runs": runs,
        "warmups": warmups,
        "program": program,
        "output": first_out,
        "rss_enabled": rss_enabled,
    }

    payload = {"meta": meta, "results": results}
    if rss_enabled and rss_results:
        payload["rss"] = rss_results

    json_path = RESULTS_DIR / f"{program}_m2_{ts}.json"
    md_path = RESULTS_DIR / f"{program}_m2_{ts}.md"

    json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    lines = []
    lines.append(f"# {program} benchmark ({ts})")
    lines.append("")
    lines.append("## Host")
    lines.append("")
    lines.append(f"- host: {meta['host']}")
    lines.append(f"- platform: {meta['platform']}")
    lines.append(f"- machine: {meta['machine']}")
    if meta["cpu_brand"]:
        lines.append(f"- cpu: {meta['cpu_brand']}")
    if meta["cpu_cores"]:
        lines.append(f"- cpu_cores: {meta['cpu_cores']}")
    if meta["mem_bytes"]:
        lines.append(f"- mem_bytes: {meta['mem_bytes']}")
    lines.append(f"- git_rev: {meta['git_rev']}")
    lines.append(f"- runs: {runs} (warmups: {warmups})")
    lines.append("")
    lines.append("## Results (seconds)")
    lines.append("")
    lines.append("| variant | median | mean | min | max |")
    lines.append("| --- | --- | --- | --- | --- |")
    for name in ["c", "oren_c", "oren_native", "oren_obc"]:
        r = results[name]
        lines.append(
            f"| {name} | {r['median_s']:.6f} | {r['mean_s']:.6f} | {r['min_s']:.6f} | {r['max_s']:.6f} |"
        )
    if rss_enabled and rss_results:
        lines.append("")
        lines.append("## RSS (bytes)")
        lines.append("")
        lines.append("| variant | median | mean | min | max |")
        lines.append("| --- | --- | --- | --- | --- |")
        for name in ["c", "oren_c", "oren_native", "oren_obc"]:
            if name not in rss_results:
                continue
            r = rss_results[name]
            lines.append(
                f"| {name} | {r['median_bytes']} | {r['mean_bytes']} | {r['min_bytes']} | {r['max_bytes']} |"
            )
    lines.append("")
    lines.append(f"Output checksum (stdout): `{first_out}`")
    lines.append("")

    md_path.write_text("\n".join(lines), encoding="utf-8")

    print(md_path)
    print(json_path)


if __name__ == "__main__":
    main()
