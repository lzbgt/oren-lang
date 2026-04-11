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

Native package-policy execution is fail-closed for declared budget_gas,
budget_heap_bytes, or budget_cpu_ms until native has backend-equivalent
accounting for those fields. Set OREN_NATIVE_PACKAGE_POLICY_RUN_JSON=<path>
to write runner-observed wall-budget evidence as JSON. Set
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

def run_summary_payload(*, exit_code, status, elapsed_ns, src, out, profile, caps, wall_ms, budgets):
    unsupported = []
    for key in ("gas", "heap_bytes", "cpu_ms"):
        if budgets.get(key) is not None:
            unsupported.append("budget_" + key)
    cap_domains = [d for d in caps.split(",") if d]
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
        "effect_ledger": {
            "available": False,
            "reason": "native runtime effect ledger export is not implemented",
        },
        "runner_observed": {
            "available": True,
            "scope": "process-watchdog",
            "budget_status": "runner_wall_only",
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
                "limit": budgets.get("heap_bytes"),
                "enforced": False,
                "reason": "native-equivalent accounting not implemented",
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
        for key in ("gas", "heap_bytes", "cpu_ms"):
            if budgets.get(key) is not None:
                unsupported.append("budget_" + key)
        if unsupported:
            fail(
                "native package runner cannot enforce "
                + ",".join(unsupported)
                + " yet; use AVM package-policy execution or remove those declarations for native"
            )

    wall_ms = None
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
    timeout = None if wall_ms is None else wall_ms / 1000.0
    start_ns = time.monotonic_ns()
    try:
        p = subprocess.run([str(out), *prog_args], env=env, timeout=timeout)
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
