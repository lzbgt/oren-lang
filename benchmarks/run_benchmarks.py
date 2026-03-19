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
RESULTS_DIR = ROOT / "build" / "benchmarks" / "results"

DEFAULT_RUNS = 5
DEFAULT_WARMUPS = 1
DEFAULT_RSS = 0
DEFAULT_INIT_SPLIT_REPS = 10
DEFAULT_LOOP_SUM_N = 20000000
ALLOC_SITE_RE = re.compile(
    r"\[alloc_site\]\s+total=(\d+)\s+list_header=(\d+)\s+list_int_header=(\d+)\s+"
    r"list_buf=(\d+)\s+list_int_buf=(\d+)"
)
ARENA_RE = re.compile(
    r"\[arena\]\s+allocs=(\d+)\s+alloc_bytes=(\d+)\s+spills=(\d+)\s+spill_bytes=(\d+)\s+"
    r"push=(\d+)\s+pop=(\d+)\s+epoch_reset=(\d+)\s+mmap_fail=(\d+)"
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


def _bench_env_snapshot():
    drop_tokens = ("KEY", "TOKEN", "PASS", "SECRET")
    out = {}
    for key, val in os.environ.items():
        if not key.startswith("OREN_"):
            continue
        if any(tok in key for tok in drop_tokens):
            continue
        out[key] = val
    return dict(sorted(out.items()))


def _run(cmd, env=None, log_path=None, time_path=None, tee=False):
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
            proc = subprocess.run(
                cmd,
                cwd=ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            if proc.stdout:
                f.write(proc.stdout)
                if tee:
                    print(proc.stdout, end="")
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


def _parse_arena_output(text):
    if not text:
        return []
    out = []
    for match in ARENA_RE.finditer(text):
        out.append(
            {
                "allocs": int(match.group(1)),
                "alloc_bytes": int(match.group(2)),
                "spills": int(match.group(3)),
                "spill_bytes": int(match.group(4)),
                "push": int(match.group(5)),
                "pop": int(match.group(6)),
                "epoch_reset": int(match.group(7)),
                "mmap_fail": int(match.group(8)),
            }
        )
    return out


def _time_cmd(
    cmd,
    runs,
    warmups,
    env=None,
    rss_enabled=False,
    rss_dir=None,
    collect_output=False,
    run_log_path=None,
    run_log_tee=False,
):
    for _ in range(warmups):
        _run(cmd, env=env)
    times = []
    rss = []
    out_sample = None
    out_all = []
    for run_idx in range(runs):
        time_path = None
        if rss_enabled and rss_dir is not None:
            time_path = rss_dir / f"time_{len(times)}.log"
        log_path = None
        if run_log_path is not None:
            log_path = run_log_path / f"run_{run_idx}.log"
        dt, out = _run(cmd, env=env, time_path=time_path, log_path=log_path, tee=run_log_tee)
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


def _stats_summary(values):
    if not values:
        return None
    med = statistics.median(values)
    mean = statistics.mean(values)
    min_v = min(values)
    max_v = max(values)
    stdev = 0.0
    cov = 0.0
    if len(values) >= 2:
        stdev = statistics.stdev(values)
        if mean != 0:
            cov = stdev / mean
    return {
        "runs": values,
        "median_s": med,
        "mean_s": mean,
        "min_s": min_v,
        "max_s": max_v,
        "stdev_s": stdev,
        "cov": cov,
    }


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
    save_run_logs: bool
    run_log_tee: bool
    collect_output: bool
    skip_obc: bool
    skip_c: bool
    skip_oren_c: bool
    skip_native: bool
    bench_args: list[str]
    init_split: bool
    init_split_reps: int
    init_split_n: int | None
    env_all: dict
    env_c: dict
    env_oren_c: dict
    env_oren_native: dict
    env_oren_obc: dict
    env_build_all: dict
    env_build_oren: dict


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


def _needs_stage2_refresh(oren_bin):
    if oren_bin is None:
        return False
    try:
        oren_bin = Path(oren_bin)
    except Exception:
        return False
    if oren_bin.name != "oren_stage2" and oren_bin.name != "oren_stage2.exe":
        return False
    stage1_bin = _resolve_exe(ROOT / "oren")
    if not oren_bin.exists():
        return True
    if stage1_bin.exists() and stage1_bin.stat().st_mtime > oren_bin.stat().st_mtime:
        return True
    return False


def _ensure_bench_compiler(oren_bin, env, ts):
    if not _needs_stage2_refresh(oren_bin):
        return
    _run(
        ["make", "oren_stage2"],
        env=env,
        log_path=LOG_DIR / f"bench_bootstrap_oren_stage2_{ts}.log",
    )


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
        build_env_base = os.environ.copy()
        build_env_base.update(cfg.env_build_all)
        build_env_oren = build_env_base.copy()
        build_env_oren.update(cfg.env_build_oren)
        _ensure_bench_compiler(oren_bin, build_env_oren, ts)
        if not cfg.skip_c:
            _run(
                _c_compile_cmd(c_compiler, c_bin, bench_dir / f"{program}.c"),
                env=build_env_base,
                log_path=LOG_DIR / f"bench_build_c_{program}_{ts}.log",
            )
        if not cfg.skip_oren_c:
            _run(
                [str(oren_bin), "build", str(bench_src), "--backend", "c", "--no-debug", "-o", str(oren_c_bin)],
                env=build_env_oren,
                log_path=LOG_DIR / f"bench_build_oren_c_{program}_{ts}.log",
            )
        if not cfg.skip_native:
            _run(
                [str(oren_bin), "build", str(bench_src), "--backend", "native", "--no-debug", "-o", str(oren_native_bin)],
                env=build_env_oren,
                log_path=LOG_DIR / f"bench_build_oren_native_{program}_{ts}.log",
            )
        if not cfg.skip_obc:
            _run(
                [str(oren_bin), "build", str(bench_src), "--backend", "bytecode", "-o", str(obc_out)],
                env=build_env_oren,
                log_path=LOG_DIR / f"bench_build_oren_obc_{program}_{ts}.log",
            )

        if not cfg.skip_obc and not avm_bin.exists():
            _run(["make", "avm"], env=build_env_base, log_path=LOG_DIR / f"bench_build_avm_{ts}.log")
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
    arena_traces = {}
    rss_results = {}

    env_base = os.environ.copy()
    run_log_root = None
    if cfg.save_run_logs:
        run_log_root = LOG_DIR / f"bench_run_{program}_{ts}"
    suite_specs = []
    if not cfg.skip_c:
        suite_specs.append(("c", cfg.env_c))
    if not cfg.skip_oren_c:
        suite_specs.append(("oren_c", cfg.env_oren_c))
    if not cfg.skip_native:
        suite_specs.append(("oren_native", cfg.env_oren_native))
    if not cfg.skip_obc:
        suite_specs.append(("oren_obc", cfg.env_oren_obc))

    def _build_cmd(name, args):
        if name == "c":
            return [str(c_bin), *args]
        if name == "oren_c":
            return [str(oren_c_bin), *args]
        if name == "oren_native":
            return [str(oren_native_bin), *args]
        if name == "oren_obc":
            # AVM args are the list after `--` (no implicit argv[0]); inject obc path as argv[0]
            # to match native/C semantics and keep cross-backend benchmarks aligned.
            obc_args = [str(obc_out), *args]
            return [str(avm_bin), str(obc_out), "--", *obc_args]
        raise RuntimeError(f"unknown benchmark variant: {name}")

    suites = [(name, _build_cmd(name, cfg.bench_args), extra_env) for name, extra_env in suite_specs]
    variant_order = [name for name, _ in suite_specs]

    for name, cmd, extra_env in suites:
        env = env_base.copy()
        env.update(cfg.env_all)
        env.update(extra_env)
        rss_dir = None
        if cfg.rss_enabled:
            rss_dir = LOG_DIR / f"bench_rss_{name}_{ts}"
        run_log_path = None
        if run_log_root is not None:
            run_log_path = run_log_root / name
        times, rss, out = _time_cmd(
            cmd,
            runs=cfg.runs,
            warmups=cfg.warmups,
            env=env,
            rss_enabled=cfg.rss_enabled,
            rss_dir=rss_dir,
            collect_output=cfg.collect_output,
            run_log_path=run_log_path,
            run_log_tee=cfg.run_log_tee,
        )
        results[name] = _stats_summary(times)
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
        arena_runs = _parse_arena_output(out)
        if arena_runs:
            arena_traces[name] = arena_runs

    init_split = {}
    if cfg.init_split and program == "loop_sum" and suite_specs:
        split_reps = cfg.init_split_reps
        if split_reps < 2:
            raise RuntimeError("OREN_BENCH_INIT_SPLIT_REPS must be >= 2")
        split_n = cfg.init_split_n
        if split_n is None:
            if cfg.bench_args:
                try:
                    split_n = int(cfg.bench_args[0])
                except ValueError:
                    split_n = DEFAULT_LOOP_SUM_N
            else:
                split_n = DEFAULT_LOOP_SUM_N
        split_args_short = [str(split_n), "1"]
        split_args_long = [str(split_n), str(split_reps)]
        for name, extra_env in suite_specs:
            env = env_base.copy()
            env.update(cfg.env_all)
            env.update(extra_env)
            cmd_short = _build_cmd(name, split_args_short)
            cmd_long = _build_cmd(name, split_args_long)
            times_short, _, _ = _time_cmd(
                cmd_short,
                runs=cfg.runs,
                warmups=cfg.warmups,
                env=env,
                rss_enabled=False,
            )
            times_long, _, _ = _time_cmd(
                cmd_long,
                runs=cfg.runs,
                warmups=cfg.warmups,
                env=env,
                rss_enabled=False,
            )
            med_short = statistics.median(times_short)
            med_long = statistics.median(times_long)
            steady = (med_long - med_short) / (split_reps - 1)
            init = med_short - steady
            init_split[name] = {
                "n": split_n,
                "reps_short": 1,
                "reps_long": split_reps,
                "median_short_s": med_short,
                "median_long_s": med_long,
                "init_s": init,
                "steady_s": steady,
            }

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
            "build_all": cfg.env_build_all,
            "build_oren": cfg.env_build_oren,
        },
    }

    env_snapshot = _bench_env_snapshot()
    payload = {"meta": meta, "results": results}
    if env_snapshot:
        payload["env"] = env_snapshot
    if init_split:
        payload["init_split"] = init_split
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
    if arena_traces:
        arena_summary = {}
        for name, runs in arena_traces.items():
            if not runs:
                continue
            def _med_arena(key):
                return int(statistics.median([r[key] for r in runs]))
            def _mean_arena(key):
                return int(statistics.mean([r[key] for r in runs]))
            arena_summary[name] = {
                "runs": runs,
                "median": {
                    "allocs": _med_arena("allocs"),
                    "alloc_bytes": _med_arena("alloc_bytes"),
                    "spills": _med_arena("spills"),
                    "spill_bytes": _med_arena("spill_bytes"),
                    "push": _med_arena("push"),
                    "pop": _med_arena("pop"),
                    "epoch_reset": _med_arena("epoch_reset"),
                    "mmap_fail": _med_arena("mmap_fail"),
                },
                "mean": {
                    "allocs": _mean_arena("allocs"),
                    "alloc_bytes": _mean_arena("alloc_bytes"),
                    "spills": _mean_arena("spills"),
                    "spill_bytes": _mean_arena("spill_bytes"),
                    "push": _mean_arena("push"),
                    "pop": _mean_arena("pop"),
                    "epoch_reset": _mean_arena("epoch_reset"),
                    "mmap_fail": _mean_arena("mmap_fail"),
                },
            }
        if arena_summary:
            payload["arena_trace"] = arena_summary

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
    if env_snapshot:
        lines.append("## Env (OREN_*)")
        lines.append("")
        for key, val in env_snapshot.items():
            lines.append(f"- {key}={val}")
        lines.append("")
    lines.append("## Results (seconds)")
    lines.append("")
    lines.append("| variant | median | mean | stdev | cov | min | max |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- |")
    for name in variant_order:
        r = results[name]
        lines.append(
            f"| {name} | {r['median_s']:.6f} | {r['mean_s']:.6f} | {r['stdev_s']:.6f} | {r['cov']:.4f} | {r['min_s']:.6f} | {r['max_s']:.6f} |"
        )
    lines.append("")
    lines.append("## Raw timing vectors (seconds)")
    lines.append("")
    for name in variant_order:
        r = results[name]
        runs = ", ".join(f"{v:.6f}" for v in r["runs"])
        lines.append(f"- {name}: [{runs}]")
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
    if arena_traces:
        lines.append("")
        lines.append("## Arena trace (median counts)")
        lines.append("")
        lines.append("| variant | allocs | alloc_bytes | spills | spill_bytes | push | pop | epoch_reset | mmap_fail |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
        for name in variant_order:
            if name not in arena_traces:
                continue
            runs = arena_traces[name]
            if not runs:
                continue
            def _med_arena_line(key):
                return int(statistics.median([r[key] for r in runs]))
            lines.append(
                f"| {name} | {_med_arena_line('allocs')} | {_med_arena_line('alloc_bytes')} | "
                f"{_med_arena_line('spills')} | {_med_arena_line('spill_bytes')} | "
                f"{_med_arena_line('push')} | {_med_arena_line('pop')} | "
                f"{_med_arena_line('epoch_reset')} | {_med_arena_line('mmap_fail')} |"
            )
    if init_split:
        lines.append("")
        lines.append("## Init/steady split (seconds)")
        lines.append("")
        lines.append("| variant | n | reps_short | reps_long | median_short | median_long | init | steady |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
        for name in variant_order:
            if name not in init_split:
                continue
            r = init_split[name]
            lines.append(
                f"| {name} | {r['n']} | {r['reps_short']} | {r['reps_long']} | "
                f"{r['median_short_s']:.6f} | {r['median_long_s']:.6f} | "
                f"{r['init_s']:.6f} | {r['steady_s']:.6f} |"
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
    save_run_logs = int(os.environ.get("OREN_BENCH_SAVE_RUN_LOGS", "0")) == 1
    run_log_tee = int(os.environ.get("OREN_BENCH_RUN_LOG_TEE", "0")) == 1
    skip_obc = int(os.environ.get("OREN_BENCH_SKIP_OBC", "0")) == 1
    skip_c = int(os.environ.get("OREN_BENCH_SKIP_C", "0")) == 1
    skip_oren_c = int(os.environ.get("OREN_BENCH_SKIP_OREN_C", "0")) == 1
    skip_native = int(os.environ.get("OREN_BENCH_SKIP_NATIVE", "0")) == 1
    program_raw = os.environ.get("OREN_BENCH_PROGRAM", "loop_sum").strip() or "loop_sum"
    programs_raw = os.environ.get("OREN_BENCH_PROGRAMS", "").strip()
    bench_args_raw = os.environ.get("OREN_BENCH_ARGS", "")
    bench_args = shlex.split(bench_args_raw) if bench_args_raw else []
    init_split = int(os.environ.get("OREN_BENCH_INIT_SPLIT", "0")) == 1
    init_split_reps_raw = os.environ.get("OREN_BENCH_INIT_SPLIT_REPS", str(DEFAULT_INIT_SPLIT_REPS)).strip()
    init_split_n_raw = os.environ.get("OREN_BENCH_INIT_SPLIT_N", "").strip()
    trace_alloc_site = int(os.environ.get("OREN_BENCH_TRACE_ALLOC_SITE", "0")) == 1
    trace_alloc_site_cap = os.environ.get("OREN_BENCH_TRACE_ALLOC_SITE_CAP", "").strip()
    trace_alloc_site_gc_threshold = os.environ.get(
        "OREN_BENCH_TRACE_ALLOC_SITE_GC_THRESHOLD", ""
    ).strip()
    trace_arena = int(os.environ.get("OREN_BENCH_TRACE_ARENA", "0")) == 1
    trace_arena_cap = os.environ.get("OREN_BENCH_TRACE_ARENA_CAP_BYTES", "").strip()
    env_all = _parse_env_overrides(os.environ.get("OREN_BENCH_ENV_ALL", ""))
    env_c = _parse_env_overrides(os.environ.get("OREN_BENCH_ENV_C", ""))
    env_oren_c = _parse_env_overrides(os.environ.get("OREN_BENCH_ENV_OREN_C", ""))
    env_oren_native = _parse_env_overrides(os.environ.get("OREN_BENCH_ENV_OREN_NATIVE", ""))
    env_oren_obc = _parse_env_overrides(os.environ.get("OREN_BENCH_ENV_OREN_OBC", ""))
    env_build_all = _parse_env_overrides(os.environ.get("OREN_BENCH_ENV_BUILD", ""))
    env_build_oren = _parse_env_overrides(os.environ.get("OREN_BENCH_ENV_BUILD_OREN", ""))
    try:
        init_split_reps = int(init_split_reps_raw)
    except ValueError as exc:
        raise RuntimeError(f"invalid OREN_BENCH_INIT_SPLIT_REPS={init_split_reps_raw!r}") from exc
    init_split_n = None
    if init_split_n_raw:
        try:
            init_split_n = int(init_split_n_raw)
        except ValueError as exc:
            raise RuntimeError(f"invalid OREN_BENCH_INIT_SPLIT_N={init_split_n_raw!r}") from exc

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
    if trace_arena:
        if output_check:
            output_check = False
        if not save_stdout:
            save_stdout = True
        env_oren_native = dict(env_oren_native)
        env_oren_native["OREN_TRACE_ARENA"] = "1"
        if trace_arena_cap:
            env_oren_native["OREN_ARENA_CAP_BYTES"] = trace_arena_cap
    if run_log_tee and not save_run_logs:
        save_run_logs = True

    collect_output = trace_alloc_site or trace_arena
    config = BenchConfig(
        runs=runs,
        warmups=warmups,
        rss_enabled=rss_enabled,
        output_check=output_check,
        skip_build=skip_build,
        save_stdout=save_stdout,
        save_run_logs=save_run_logs,
        run_log_tee=run_log_tee,
        collect_output=collect_output,
        skip_obc=skip_obc,
        skip_c=skip_c,
        skip_oren_c=skip_oren_c,
        skip_native=skip_native,
        bench_args=bench_args,
        init_split=init_split,
        init_split_reps=init_split_reps,
        init_split_n=init_split_n,
        env_all=env_all,
        env_c=env_c,
        env_oren_c=env_oren_c,
        env_oren_native=env_oren_native,
        env_oren_obc=env_oren_obc,
        env_build_all=env_build_all,
        env_build_oren=env_build_oren,
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
