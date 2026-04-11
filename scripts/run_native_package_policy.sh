#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat >&2 <<'EOF'
usage: scripts/run_native_package_policy.sh <source.oren> [-- <program-args...>]

Builds <source.oren> with metadata/artifact manifests, reads
policy.source_package, then runs a native artifact with the declared package
policy subset that native can enforce today:
  - runtime_profile="capsule" -> native --capsule plus OREN_CAPSULE=1
  - cap_allow_domains -> native --cap-allow-domains plus OREN_CAP_ALLOW_DOMAINS
  - budget_wall_ms -> runner process watchdog
  - budget_heap_bytes -> native-run JSON live-heap scan check

Native package-policy execution is fail-closed for declared budget_gas or
budget_cpu_ms until native has backend-equivalent accounting for those fields.
Set OREN_NATIVE_PACKAGE_POLICY_RUN_JSON=<path> to write runner-observed
wall-budget evidence plus any captured native runtime ledger summary as JSON. Set
OREN_NATIVE_PACKAGE_POLICY_KEEP_BIN=1, or provide OREN_NATIVE_PACKAGE_POLICY_OUT,
to keep generated artifacts.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$#" -lt 1 ]]; then
  usage
  exit 2
fi

src="$1"
shift
if [[ "$#" -gt 0 && "${1:-}" == "--" ]]; then
  shift
fi

if [[ ! -f "$src" ]]; then
  echo "ERROR: missing source: $src" >&2
  exit 2
fi

mkdir -p build/logs build/tmp

python3 - "$src" -- "$@" <<'PY'
import json
import os
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path

NATIVE_DOMAINS = {"FS", "NET", "PROC", "ENV", "TIME", "RNG"}

def fail(msg, rc=2):
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(rc)

def positive_int(value, name):
    try:
        out = int(value)
    except (TypeError, ValueError):
        fail(f"{name} must be a positive integer, got {value!r}")
    if out <= 0:
        fail(f"{name} must be a positive integer, got {value!r}")
    return out

def split_prog_args(args):
    if args and args[0] == "--":
        return args[1:]
    return args

def domain_csv(domains):
    out = []
    seen = set()
    for raw in domains or []:
        name = str(raw).strip().upper()
        if not name:
            continue
        if name not in NATIVE_DOMAINS:
            fail(f"native package runner cannot map domain {name!r}; supported domains are {sorted(NATIVE_DOMAINS)!r}")
        if name not in seen:
            seen.add(name)
            out.append(name)
    return ",".join(out)

def read_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def run_checked(cmd, *, env=None, log_path=None):
    if log_path is None:
        p = subprocess.run(cmd, env=env)
    else:
        with open(log_path, "w", encoding="utf-8") as log:
            p = subprocess.run(cmd, env=env, stdout=log, stderr=subprocess.STDOUT, text=True)
    if p.returncode != 0:
        if log_path is not None:
            try:
                print(Path(log_path).read_text(encoding="utf-8"), end="", file=sys.stderr)
            except OSError:
                pass
        raise SystemExit(p.returncode)

def extract_native_run_json(stdout_text):
    found = None
    for raw in stdout_text.splitlines():
        line = raw.strip()
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("schema") == "oren.native-run.v0":
            found = obj
    return found

def native_heap_used_from_run_json(native_run_json):
    if not native_run_json:
        return None
    summary = native_run_json.get("effect_ledger_summary") or {}
    heap = ((summary.get("budgets") or {}).get("heap_bytes") or {})
    used = heap.get("used")
    if used is None:
        return None
    try:
        return int(used)
    except (TypeError, ValueError):
        return None

src = sys.argv[1]
prog_args = split_prog_args(sys.argv[2:])
if prog_args and prog_args[0] == "--":
    prog_args = prog_args[1:]

ts = time.strftime("%Y%m%d_%H%M%S")
stem = "".join(ch if ch.isalnum() or ch in "_-" else "_" for ch in Path(src).stem)
tmp_dir = Path("build/tmp") / f"native_package_policy_{stem}_{ts}"
tmp_dir.mkdir(parents=True, exist_ok=True)

exe_ext = ".exe" if platform.system().lower().startswith("windows") else ""
out = Path(os.environ.get("OREN_NATIVE_PACKAGE_POLICY_OUT", str(tmp_dir / f"{stem}{exe_ext}")))
meta_out = tmp_dir / f"{stem}.metadata.json"
build_log = os.environ.get("OREN_NATIVE_PACKAGE_POLICY_BUILD_LOG", f"build/logs/native_package_policy_{stem}_{ts}.build.log")
run_json_path = os.environ.get("OREN_NATIVE_PACKAGE_POLICY_RUN_JSON", "")
keep = bool(os.environ.get("OREN_NATIVE_PACKAGE_POLICY_KEEP_BIN") or os.environ.get("OREN_NATIVE_PACKAGE_POLICY_OUT"))

def write_run_json(payload):
    if not run_json_path:
        return
    data = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if run_json_path == "-":
        print(data, end="")
        return
    out_path = Path(run_json_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(data, encoding="utf-8")

def run_summary_payload(*, exit_code, status, elapsed_ns, src, out, profile, caps, wall_ms, budgets, native_run_json=None):
    unsupported = []
    for key in ("gas", "cpu_ms"):
        if budgets.get(key) is not None:
            unsupported.append("budget_" + key)
    cap_domains = [d for d in caps.split(",") if d]
    native_summary = None
    if native_run_json:
        native_summary = native_run_json.get("effect_ledger_summary") or None
    heap_limit = budgets.get("heap_bytes")
    heap_used = native_heap_used_from_run_json(native_run_json)
    heap_enforced = heap_limit is not None and heap_used is not None
    heap_exceeded = bool(heap_enforced and heap_used > int(heap_limit))
    if native_summary is not None:
        effect_ledger = {
            "available": True,
            "source": "native-runtime",
            "schema": native_summary.get("schema"),
            "summary": native_summary,
        }
    else:
        effect_ledger = {
            "available": False,
            "reason": "native runtime effect ledger export was not captured for this run",
        }
    return {
        "schema": "oren.native-package-policy-run.v0",
        "backend": "native",
        "source": str(src),
        "executable": str(out),
        "status": status,
        "exit_code": exit_code,
        "runtime_profile": profile,
        "capsule": profile == "capsule",
        "cap_allow_domains": cap_domains,
        "effect_ledger": effect_ledger,
        "runner_observed": {
            "available": True,
            "scope": "process-watchdog+native-run-json" if native_summary is not None else "process-watchdog",
            "budget_status": "runner_wall_native_heap" if heap_enforced else "runner_wall_only",
        },
        "budgets": {
            "declared": bool(budgets.get("declared")),
            "unsupported": unsupported,
            "wall_ms": {
                "limit": wall_ms,
                "elapsed_ns": elapsed_ns,
                "enforced": wall_ms is not None,
                "enforcement": "runner-watchdog" if wall_ms is not None else "none",
            },
            "gas": {
                "limit": budgets.get("gas"),
                "enforced": False,
                "reason": "native-equivalent accounting not implemented",
            },
            "heap_bytes": {
                "limit": heap_limit,
                "used": heap_used,
                "enforced": heap_enforced,
                "enforcement": "native-run-json-live-scan" if heap_enforced else "none",
                "exceeded": heap_exceeded,
                "reason": None if heap_enforced or heap_limit is None else "native runtime heap summary was not captured",
            },
            "cpu_ms": {
                "limit": budgets.get("cpu_ms"),
                "enforced": False,
                "reason": "native-equivalent accounting not implemented",
            },
        },
    }

try:
    run_checked(["./oren", "meta", src, "--manifest", "-o", str(meta_out)], log_path=f"build/logs/native_package_policy_{stem}_{ts}.meta.log")
    manifest = read_json(str(meta_out) + ".manifest.json")
    pkg = ((manifest.get("policy") or {}).get("source_package") or {})
    if not pkg.get("declared"):
        fail(f"{meta_out}.manifest.json: missing declared policy.source_package")

    profile = pkg.get("runtime_profile")
    if profile != "capsule":
        fail(f"native package runner currently requires runtime_profile=\"capsule\", got {profile!r}")

    budgets = pkg.get("budgets") or {}
    if budgets.get("declared"):
        unsupported = []
        for key in ("gas", "cpu_ms"):
            if budgets.get(key) is not None:
                unsupported.append("budget_" + key)
        if unsupported:
            fail(
                "native package runner cannot enforce "
                + ",".join(unsupported)
                + " yet; use AVM package-policy execution or remove those declarations for native"
            )

    wall_ms = None
    heap_limit = None
    if budgets.get("heap_bytes") is not None:
        heap_limit = positive_int(budgets.get("heap_bytes"), "budget_heap_bytes")
    if budgets.get("wall_ms") is not None:
        wall_ms = positive_int(budgets.get("wall_ms"), "budget_wall_ms")
    env_wall = os.environ.get("OREN_NATIVE_PACKAGE_POLICY_TIMEOUT_MS")
    if env_wall:
        env_wall_i = positive_int(env_wall, "OREN_NATIVE_PACKAGE_POLICY_TIMEOUT_MS")
        wall_ms = env_wall_i if wall_ms is None else min(wall_ms, env_wall_i)

    caps = domain_csv(pkg.get("cap_allow_domains") or [])
    build_cmd = [
        "./oren", "build", src,
        "--backend", "native",
        "--capsule",
        "--manifest",
        "--enforce-package-policy",
        "--cap-allow-domains", caps,
        "--no-debug",
        "-o", str(out),
    ]
    run_checked(build_cmd, log_path=build_log)

    env = os.environ.copy()
    env["OREN_CAPSULE"] = "1"
    env["OREN_CAP_ALLOW_DOMAINS"] = caps
    capture_native_run_json = bool(run_json_path or heap_limit is not None)
    if capture_native_run_json:
        env["OREN_NATIVE_RUN_JSON"] = "1"
    timeout = None if wall_ms is None else wall_ms / 1000.0
    start_ns = time.monotonic_ns()
    try:
        if capture_native_run_json:
            p = subprocess.run(
                [str(out), *prog_args],
                env=env,
                timeout=timeout,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            sys.stdout.write(p.stdout or "")
            sys.stderr.write(p.stderr or "")
            native_run_json = extract_native_run_json(p.stdout or "")
        else:
            p = subprocess.run([str(out), *prog_args], env=env, timeout=timeout)
            native_run_json = None
    except subprocess.TimeoutExpired:
        elapsed_ns = time.monotonic_ns() - start_ns
        write_run_json(run_summary_payload(
            exit_code=124,
            status="timeout",
            elapsed_ns=elapsed_ns,
            src=src,
            out=out,
            profile=profile,
            caps=caps,
            wall_ms=wall_ms,
            budgets=budgets,
        ))
        fail(f"package native wall budget exceeded: {wall_ms}ms", rc=124)
    elapsed_ns = time.monotonic_ns() - start_ns
    if heap_limit is not None:
        heap_used = native_heap_used_from_run_json(native_run_json)
        if heap_used is None:
            write_run_json(run_summary_payload(
                exit_code=76,
                status="budget_unavailable",
                elapsed_ns=elapsed_ns,
                src=src,
                out=out,
                profile=profile,
                caps=caps,
                wall_ms=wall_ms,
                budgets=budgets,
                native_run_json=native_run_json,
            ))
            fail("package native heap budget cannot be checked: native runtime heap summary was not captured", rc=76)
        if heap_used > heap_limit:
            write_run_json(run_summary_payload(
                exit_code=125,
                status="budget_exceeded",
                elapsed_ns=elapsed_ns,
                src=src,
                out=out,
                profile=profile,
                caps=caps,
                wall_ms=wall_ms,
                budgets=budgets,
                native_run_json=native_run_json,
            ))
            fail(f"package native heap budget exceeded: used {heap_used} bytes > limit {heap_limit} bytes", rc=125)
    write_run_json(run_summary_payload(
        exit_code=p.returncode,
        status="pass" if p.returncode == 0 else "fail",
        elapsed_ns=elapsed_ns,
        src=src,
        out=out,
        profile=profile,
        caps=caps,
        wall_ms=wall_ms,
        budgets=budgets,
        native_run_json=native_run_json,
    ))
    raise SystemExit(p.returncode)
finally:
    if not keep:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        try:
            Path(str(out) + ".manifest.json").unlink()
        except OSError:
            pass
PY
