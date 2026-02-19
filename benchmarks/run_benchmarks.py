#!/usr/bin/env python3
import json
import os
import platform
import re
import shutil
import shlex
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOG_DIR = ROOT / "build" / "logs"
RESULTS_DIR = ROOT / "benchmarks" / "results"

DEFAULT_RUNS = 5
DEFAULT_WARMUPS = 1
DEFAULT_RSS = 0
ALLOC_SITE_RE = re.compile(
    r"\[alloc_site\]\s+total=(\d+)\s+list_header=(\d+)\s+list_int_header=(\d+)\s+"
    r"list_buf=(\d+)\s+list_int_buf=(\d+)"
)


def _parse_env_overrides(raw):
    out = {}
    if not raw:
        return out
    parts = [p.strip() for p in raw.split(",")]
    for part in parts:
        if not part:
            continue
        if "=" not in part:
            raise RuntimeError(f"invalid env override (expected KEY=VAL): {part}")
        k, v = part.split("=", 1)
        k = k.strip()
        v = v.strip()
        if not k:
            raise RuntimeError(f"invalid env override (empty key): {part}")
        out[k] = v
    return out


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


def _parse_alloc_site_output(text):
    if not text:
        return []
    out = []
    for match in ALLOC_SITE_RE.finditer(text):
        out.append(
            {
                "total": int(match.group(1)),
                "list_header": int(match.group(2)),
                "list_int_header": int(match.group(3)),
                "list_buf": int(match.group(4)),
                "list_int_buf": int(match.group(5)),
            }
        )
    return out


def _time_cmd(cmd, runs, warmups, env=None, rss_enabled=False, rss_dir=None, collect_output=False):
    for _ in range(warmups):
        _run(cmd, env=env)
    times = []
    rss = []
    out_sample = None
    out_all = []
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
        if collect_output:
            if out:
                out_all.append(out.strip())
        elif out_sample is None:
            out_sample = out.strip()
    if collect_output:
        return times, rss, "\n".join([s for s in out_all if s])
    return times, rss, out_sample


def _sysctl_value(key):
    try:
        out = subprocess.check_output(["sysctl", "-n", key], cwd=ROOT).decode("utf-8").strip()
        return out
    except Exception:
        return ""


def _sanitize_tag(value):
    cleaned = "".join(ch if ch.isalnum() else "_" for ch in value)
    cleaned = cleaned.strip("_")
    return cleaned or "host"


def _host_tag():
    return _sanitize_tag(f"{platform.system().lower()}_{platform.machine().lower()}")


def _resolve_exe(path):
    if platform.system() != "Windows":
        return path
    if path.suffix:
        return path
    exe_path = path.with_suffix(".exe")
    if exe_path.exists():
        return exe_path
    return path


def _pick_c_compiler():
    override = os.environ.get("OREN_BENCH_CC")
    if override:
        return override
    if platform.system() == "Windows":
        candidates = ["cc", "clang", "gcc", "cl"]
    else:
        candidates = ["cc", "clang", "gcc"]
    for name in candidates:
        if shutil.which(name):
            return name
    return "cc"


def _is_msvc(compiler):
    name = Path(compiler).name.lower()
    return name in {"cl", "cl.exe"}


def _c_compile_cmd(compiler, output, source):
    if _is_msvc(compiler):
        return [compiler, "/nologo", "/O2", str(source), f"/Fe:{output}"]
    return [compiler, "-O2", "-o", str(output), str(source)]


@dataclass(frozen=True)
class BenchConfig:
    runs: int
    warmups: int
    rss_enabled: bool
    output_check: bool
    skip_build: bool
    save_stdout: bool
    collect_output: bool
    skip_obc: bool
    skip_c: bool
    skip_oren_c: bool
    skip_native: bool
    bench_args: list[str]
    env_all: dict
    env_c: dict
    env_oren_c: dict
    env_oren_native: dict
    env_oren_obc: dict


def _split_program_list(raw):
    parts = re.split(r"[\s,]+", raw.strip())
    return [p for p in parts if p]


def _discover_programs(bench_root):
    programs = []
    for entry in bench_root.iterdir():
        if not entry.is_dir():
            continue
        if (entry / f"{entry.name}.oren").exists():
            programs.append(entry.name)
    return sorted(programs)


def _resolve_programs(bench_root, program_raw, programs_raw):
    if programs_raw:
        programs = _split_program_list(programs_raw)
    elif program_raw.lower() == "all":
        programs = _discover_programs(bench_root)
    elif "," in program_raw:
        programs = _split_program_list(program_raw)
    else:
        programs = [program_raw]
    if not programs:
        raise RuntimeError("no benchmarks selected (set OREN_BENCH_PROGRAM or OREN_BENCH_PROGRAMS)")
    return programs


def _run_one(program, cfg: BenchConfig):
    bench_dir = ROOT / "benchmarks" / program
    bench_src = bench_dir / f"{program}.oren"
    if not bench_dir.exists() or not bench_src.exists():
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

    if platform.system() == "Windows":
        c_bin = c_bin.with_suffix(".exe")
        oren_c_bin = oren_c_bin.with_suffix(".exe")
        oren_native_bin = oren_native_bin.with_suffix(".exe")

    avm_bin = _resolve_exe(ROOT / "avm")
    oren_bin = _resolve_exe(ROOT / "oren_stage2")
    c_compiler = _pick_c_compiler()

    if not cfg.skip_build:
        if not cfg.skip_c:
            _run(
                _c_compile_cmd(c_compiler, c_bin, bench_dir / f"{program}.c"),
                log_path=LOG_DIR / f"bench_build_c_{program}_{ts}.log",
            )
        if not cfg.skip_oren_c:
            _run(
                [str(oren_bin), "build", str(bench_src), "--backend", "c", "--no-debug", "-o", str(oren_c_bin)],
                log_path=LOG_DIR / f"bench_build_oren_c_{program}_{ts}.log",
            )
        if not cfg.skip_native:
            _run(
                [str(oren_bin), "build", str(bench_src), "--backend", "native", "--no-debug", "-o", str(oren_native_bin)],
                log_path=LOG_DIR / f"bench_build_oren_native_{program}_{ts}.log",
            )
        if not cfg.skip_obc:
            _run(
                [str(oren_bin), "build", str(bench_src), "--backend", "bytecode", "-o", str(obc_out)],
                log_path=LOG_DIR / f"bench_build_oren_obc_{program}_{ts}.log",
            )

        if not cfg.skip_obc and not avm_bin.exists():
            _run(["make", "avm"], log_path=LOG_DIR / f"bench_build_avm_{ts}.log")
    else:
        if not cfg.skip_c and not c_bin.exists():
            raise RuntimeError(f"missing C binary for {program}: {c_bin} (disable OREN_BENCH_SKIP_BUILD)")
        if not cfg.skip_oren_c and not oren_c_bin.exists():
            raise RuntimeError(f"missing Oren C binary for {program}: {oren_c_bin} (disable OREN_BENCH_SKIP_BUILD)")
        if not cfg.skip_native and not oren_native_bin.exists():
            raise RuntimeError(f"missing native binary for {program}: {oren_native_bin} (disable OREN_BENCH_SKIP_BUILD)")
        if not cfg.skip_obc and not obc_out.exists():
            raise RuntimeError(f"missing OBC output for {program}: {obc_out} (disable OREN_BENCH_SKIP_BUILD)")
        if not cfg.skip_obc and not avm_bin.exists():
            raise RuntimeError(f"missing AVM binary: {avm_bin} (disable OREN_BENCH_SKIP_BUILD)")

    results = {}
    outputs = {}
    alloc_sites = {}
    rss_results = {}

    env_base = os.environ.copy()
    suites = []
    if not cfg.skip_c:
        suites.append(("c", [str(c_bin), *cfg.bench_args], cfg.env_c))
    if not cfg.skip_oren_c:
        suites.append(("oren_c", [str(oren_c_bin), *cfg.bench_args], cfg.env_oren_c))
    if not cfg.skip_native:
        suites.append(("oren_native", [str(oren_native_bin), *cfg.bench_args], cfg.env_oren_native))
    if not cfg.skip_obc:
        # AVM args are the list after `--` (no implicit argv[0]); inject obc path as argv[0]
        # to match native/C semantics and keep cross-backend benchmarks aligned.
        obc_args = [str(obc_out), *cfg.bench_args]
        obc_cmd = [str(avm_bin), str(obc_out), "--", *obc_args]
        suites.append(("oren_obc", obc_cmd, cfg.env_oren_obc))
    variant_order = [name for name, _, _ in suites]

    for name, cmd, extra_env in suites:
        env = env_base.copy()
        env.update(cfg.env_all)
        env.update(extra_env)
        rss_dir = None
        if cfg.rss_enabled:
            rss_dir = LOG_DIR / f"bench_rss_{name}_{ts}"
        times, rss, out = _time_cmd(
            cmd,
            runs=cfg.runs,
            warmups=cfg.warmups,
            env=env,
            rss_enabled=cfg.rss_enabled,
            rss_dir=rss_dir,
            collect_output=cfg.collect_output,
        )
        results[name] = {
            "runs": times,
            "median_s": statistics.median(times),
            "mean_s": statistics.mean(times),
            "min_s": min(times),
            "max_s": max(times),
        }
        if cfg.rss_enabled and rss:
            rss_results[name] = {
                "runs": rss,
                "median_bytes": int(statistics.median(rss)),
                "mean_bytes": int(statistics.mean(rss)),
                "min_bytes": min(rss),
                "max_bytes": max(rss),
            }
        outputs[name] = out
        alloc_runs = _parse_alloc_site_output(out)
        if alloc_runs:
            alloc_sites[name] = alloc_runs

    if cfg.save_stdout:
        for name, out in outputs.items():
            out_path = LOG_DIR / f"bench_stdout_{program}_{name}_{ts}.log"
            out_path.write_text(out + "\n", encoding="utf-8")

    # Output consistency check (can be disabled for tracing/instrumentation).
    first_out = None
    for name, out in outputs.items():
        if first_out is None:
            first_out = out
            continue
        if cfg.output_check and out != first_out:
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
        "c_compiler": c_compiler,
        "runs": cfg.runs,
        "warmups": cfg.warmups,
        "program": program,
        "output": first_out,
        "output_check": cfg.output_check,
        "save_stdout": cfg.save_stdout,
        "skip_build": cfg.skip_build,
        "rss_enabled": cfg.rss_enabled,
        "skip_obc": cfg.skip_obc,
        "env_overrides": {
            "all": cfg.env_all,
            "c": cfg.env_c,
            "oren_c": cfg.env_oren_c,
            "oren_native": cfg.env_oren_native,
            "oren_obc": cfg.env_oren_obc,
        },
    }

    payload = {"meta": meta, "results": results}
    if cfg.rss_enabled and rss_results:
        payload["rss"] = rss_results
    if alloc_sites:
        alloc_summary = {}
        for name, runs in alloc_sites.items():
            if not runs:
                continue
            def _med(key):
                return int(statistics.median([r[key] for r in runs]))
            def _mean(key):
                return int(statistics.mean([r[key] for r in runs]))
            alloc_summary[name] = {
                "runs": runs,
                "median": {
                    "total": _med("total"),
                    "list_header": _med("list_header"),
                    "list_int_header": _med("list_int_header"),
                    "list_buf": _med("list_buf"),
                    "list_int_buf": _med("list_int_buf"),
                },
                "mean": {
                    "total": _mean("total"),
                    "list_header": _mean("list_header"),
                    "list_int_header": _mean("list_int_header"),
                    "list_buf": _mean("list_buf"),
                    "list_int_buf": _mean("list_int_buf"),
                },
            }
        if alloc_summary:
            payload["alloc_site"] = alloc_summary

    host_tag = _host_tag()
    json_path = RESULTS_DIR / f"{program}_{host_tag}_{ts}.json"
    md_path = RESULTS_DIR / f"{program}_{host_tag}_{ts}.md"

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
    lines.append(f"- runs: {cfg.runs} (warmups: {cfg.warmups})")
    lines.append("")
    lines.append("## Results (seconds)")
    lines.append("")
    lines.append("| variant | median | mean | min | max |")
    lines.append("| --- | --- | --- | --- | --- |")
    for name in variant_order:
        r = results[name]
        lines.append(
            f"| {name} | {r['median_s']:.6f} | {r['mean_s']:.6f} | {r['min_s']:.6f} | {r['max_s']:.6f} |"
        )
    if cfg.rss_enabled and rss_results:
        lines.append("")
        lines.append("## RSS (bytes)")
        lines.append("")
        lines.append("| variant | median | mean | min | max |")
        lines.append("| --- | --- | --- | --- | --- |")
        for name in variant_order:
            if name not in rss_results:
                continue
            r = rss_results[name]
            lines.append(
                f"| {name} | {r['median_bytes']} | {r['mean_bytes']} | {r['min_bytes']} | {r['max_bytes']} |"
            )
    if alloc_sites:
        lines.append("")
        lines.append("## Alloc sites (median counts)")
        lines.append("")
        lines.append("| variant | total | list_header | list_int_header | list_buf | list_int_buf |")
        lines.append("| --- | --- | --- | --- | --- | --- |")
        for name in variant_order:
            if name not in alloc_sites:
                continue
            runs = alloc_sites[name]
            if not runs:
                continue
            def _med_line(key):
                return int(statistics.median([r[key] for r in runs]))
            lines.append(
                f"| {name} | {_med_line('total')} | {_med_line('list_header')} | "
                f"{_med_line('list_int_header')} | {_med_line('list_buf')} | {_med_line('list_int_buf')} |"
            )
    lines.append("")
    lines.append(f"Output checksum (stdout): `{first_out}`")
    lines.append("")

    md_path.write_text("\n".join(lines), encoding="utf-8")

    print(md_path)
    print(json_path)


def main():
    runs = int(os.environ.get("OREN_BENCH_RUNS", DEFAULT_RUNS))
    warmups = int(os.environ.get("OREN_BENCH_WARMUPS", DEFAULT_WARMUPS))
    rss_enabled = int(os.environ.get("OREN_BENCH_RSS", DEFAULT_RSS)) == 1
    output_check = int(os.environ.get("OREN_BENCH_OUTPUT_CHECK", "1")) == 1
    skip_build = int(os.environ.get("OREN_BENCH_SKIP_BUILD", "0")) == 1
    save_stdout = int(os.environ.get("OREN_BENCH_SAVE_STDOUT", "0")) == 1
    skip_obc = int(os.environ.get("OREN_BENCH_SKIP_OBC", "0")) == 1
    skip_c = int(os.environ.get("OREN_BENCH_SKIP_C", "0")) == 1
    skip_oren_c = int(os.environ.get("OREN_BENCH_SKIP_OREN_C", "0")) == 1
    skip_native = int(os.environ.get("OREN_BENCH_SKIP_NATIVE", "0")) == 1
    program_raw = os.environ.get("OREN_BENCH_PROGRAM", "loop_sum").strip() or "loop_sum"
    programs_raw = os.environ.get("OREN_BENCH_PROGRAMS", "").strip()
    bench_args_raw = os.environ.get("OREN_BENCH_ARGS", "")
    bench_args = shlex.split(bench_args_raw) if bench_args_raw else []
    trace_alloc_site = int(os.environ.get("OREN_BENCH_TRACE_ALLOC_SITE", "0")) == 1
    trace_alloc_site_cap = os.environ.get("OREN_BENCH_TRACE_ALLOC_SITE_CAP", "").strip()
    trace_alloc_site_gc_threshold = os.environ.get(
        "OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD", ""
    ).strip()
    env_all = _parse_env_overrides(os.environ.get("OREN_BENCH_ENV_ALL", ""))
    env_c = _parse_env_overrides(os.environ.get("OREN_BENCH_ENV_C", ""))
    env_oren_c = _parse_env_overrides(os.environ.get("OREN_BENCH_ENV_OREN_C", ""))
    env_oren_native = _parse_env_overrides(os.environ.get("OREN_BENCH_ENV_OREN_NATIVE", ""))
    env_oren_obc = _parse_env_overrides(os.environ.get("OREN_BENCH_ENV_OREN_OBC", ""))

    if trace_alloc_site:
        if output_check:
            output_check = False
        if not save_stdout:
            save_stdout = True
        if warmups != 0:
            warmups = 0
        env_oren_native = dict(env_oren_native)
        env_oren_native["OREN_TRACE_ALLOC_SITE"] = "1"
        if trace_alloc_site_cap:
            env_oren_native["OREN_TRACE_ALLOC_SITE_CAP"] = trace_alloc_site_cap
        if trace_alloc_site_gc_threshold:
            env_oren_native["OREN_GC_AUTO"] = "1"
            env_oren_native["OREN_GC_ALLOC_THRESHOLD"] = trace_alloc_site_gc_threshold

    config = BenchConfig(
        runs=runs,
        warmups=warmups,
        rss_enabled=rss_enabled,
        output_check=output_check,
        skip_build=skip_build,
        save_stdout=save_stdout,
        collect_output=trace_alloc_site,
        skip_obc=skip_obc,
        skip_c=skip_c,
        skip_oren_c=skip_oren_c,
        skip_native=skip_native,
        bench_args=bench_args,
        env_all=env_all,
        env_c=env_c,
        env_oren_c=env_oren_c,
        env_oren_native=env_oren_native,
        env_oren_obc=env_oren_obc,
    )

    programs = _resolve_programs(ROOT / "benchmarks", program_raw, programs_raw)
    for program in programs:
        _run_one(program, config)
    if len(programs) > 1:
        print(f"Completed {len(programs)} benchmarks: {', '.join(programs)}")

    if int(os.environ.get("OREN_BENCH_UPDATE_LATEST", "0")) == 1:
        cmd = [sys.executable, str(ROOT / "benchmarks" / "update_latest.py")]
        if int(os.environ.get("OREN_BENCH_UPDATE_LATEST_PRUNE", "0")) == 1:
            cmd.append("--prune")
        subprocess.run(cmd, cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
