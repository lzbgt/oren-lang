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
  - budget_cpu_ms -> child process CPU-time check from resource usage when supported
  - budget_gas -> native-run JSON statement+loop counter check

Native package-policy gas accounting is the scoped v0 native statement+loop
surface, not full instruction-equivalent gas and not AVM-canonical opcode gas.
The runner builds and runs gas budget fixtures with OREN_NATIVE_GAS_ACCOUNTING=stmt. budget_cpu_ms still fails
closed when child CPU usage is not available on the host.
Set OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE=avm-sidecar to enforce budget_gas
from a package-bound AVM canonical sidecar instead of native statement gas. Set
OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE=auto to choose avm-sidecar when the
package declares budget_gas.
Set OREN_NATIVE_PACKAGE_POLICY_RUN_JSON=<path> to write runner-observed
wall/gas/heap/CPU-budget evidence plus any captured native runtime ledger summary as JSON. Set
OREN_NATIVE_PACKAGE_POLICY_AVM_SIDECAR=1 to also build and run a bytecode sidecar with
the same package budgets and record AVM-canonical opcode gas as non-converting package evidence. Set
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
import hashlib
import os
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path

try:
    import resource
except ImportError:
    resource = None

NATIVE_DOMAINS = {"FS", "NET", "PROC", "ENV", "TIME", "RNG"}
AVM_DOMAIN_IDS = {
    "CORE": 0,
    "FS": 1,
    "TIME": 2,
    "RNG": 3,
    "NET": 4,
    "PROC": 5,
    "EXIT": 6,
    "ENV": 7,
    "AVM": 8,
}
NATIVE_GAS_KIND = "native_stmt_loop_tick_v0"

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

def normalize_gas_profile(value):
    raw = str(value or "native-stmt").strip().lower().replace("_", "-")
    if raw in ("", "native-stmt", "stmt", "statement"):
        return "native-stmt"
    if raw in ("avm-sidecar", "avm-canonical-sidecar"):
        return "avm-sidecar"
    if raw in ("auto", "package-auto", "package-default"):
        return "auto"
    fail(
        "OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE must be native-stmt, avm-sidecar, or auto, "
        f"got {value!r}"
    )

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

def extract_avm_run_json(stdout_text):
    found = None
    for raw in stdout_text.splitlines():
        line = raw.strip()
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("schema") == "avm.run.v1":
            found = obj
    return found

def strip_run_json_lines(stdout_text):
    lines = []
    for raw in (stdout_text or "").splitlines():
        line = raw.strip()
        if line.startswith("{"):
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                obj = None
            if isinstance(obj, dict) and obj.get("schema") in ("oren.native-run.v0", "avm.run.v1"):
                continue
        lines.append(raw.rstrip())
    return "\n".join(lines).strip()

def sha256_s(text):
    return hashlib.sha256((text or "").encode("utf-8")).hexdigest()

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

def native_gas_from_run_json(native_run_json):
    if not native_run_json:
        return (None, None, None, None)
    summary = native_run_json.get("effect_ledger_summary") or {}
    gas = ((summary.get("budgets") or {}).get("gas") or {})
    executed = gas.get("executed")
    remaining = gas.get("remaining")
    kind = gas.get("kind")
    surface = gas.get("surface")
    if executed is None:
        return (None, remaining, kind, surface)
    try:
        return (int(executed), remaining, kind, surface)
    except (TypeError, ValueError):
        return (None, remaining, kind, surface)

def avm_gas_from_run_json(avm_run_json):
    if not avm_run_json:
        return (None, None, None, None)
    summary = avm_run_json.get("effect_ledger_summary") or {}
    gas = ((summary.get("budgets") or {}).get("gas") or {})
    executed = gas.get("executed")
    remaining = gas.get("remaining")
    kind = gas.get("kind")
    surface = gas.get("surface")
    if executed is None:
        return (None, remaining, kind, surface)
    try:
        return (int(executed), remaining, kind, surface)
    except (TypeError, ValueError):
        return (None, remaining, kind, surface)

def avm_allow_domains_for_package(domains):
    domain_ids = {AVM_DOMAIN_IDS["CORE"], AVM_DOMAIN_IDS["EXIT"]}
    for raw in domains or []:
        name = str(raw).strip().upper()
        if not name:
            continue
        if name not in AVM_DOMAIN_IDS:
            fail(f"AVM sidecar cannot map package domain {name!r}")
        domain_ids.add(AVM_DOMAIN_IDS[name])
    return ",".join(str(x) for x in sorted(domain_ids))

def avm_canonical_sidecar_payload(*, src, obc, native_stdout, native_stderr, native_exit_code, avm_stdout, avm_stderr, avm_exit_code, avm_run_json):
    avm_gas_used, avm_gas_remaining, avm_gas_kind, avm_gas_surface = avm_gas_from_run_json(avm_run_json)
    native_stdout_normalized = strip_run_json_lines(native_stdout)
    avm_stdout_normalized = strip_run_json_lines(avm_stdout)
    native_stderr_normalized = strip_run_json_lines(native_stderr)
    avm_stderr_normalized = strip_run_json_lines(avm_stderr)
    same_stdout = native_stdout_normalized == avm_stdout_normalized
    same_exit = native_exit_code == avm_exit_code
    avm_run_error = None
    if isinstance(avm_run_json, dict) and isinstance(avm_run_json.get("error"), dict):
        avm_run_error = avm_run_json.get("error")
    structured_budget_exceeded = (
        isinstance(avm_run_error, dict)
        and avm_run_error.get("code") == 9
        and avm_run_error.get("msg") == "budget exceeded (gas)"
    )
    stderr_budget_exceeded = "budget exceeded (gas)" in (avm_stderr or "")
    budget_exceeded = structured_budget_exceeded or stderr_budget_exceeded
    budget_exceeded_source = (
        "avm_run_json_error"
        if structured_budget_exceeded
        else ("stderr_diagnostic" if stderr_budget_exceeded else None)
    )
    canonical_surface = (
        isinstance(avm_gas_surface, dict)
        and avm_gas_surface.get("id") == "avm_opcode_cost_v0"
        and avm_gas_surface.get("unit_scope") == "avm_canonical"
        and avm_gas_surface.get("conversion_ready") is True
        and avm_gas_surface.get("avm_canonical") is True
    )
    canonical_positive_gas = (
        canonical_surface
        and avm_gas_used is not None
        and avm_gas_used > 0
    )
    available = bool(same_stdout and same_exit and canonical_positive_gas and avm_exit_code == 0)
    package_policy_may_use = available or (
        budget_exceeded
        and canonical_surface
    )
    certification_failure_reasons = []
    if not same_stdout:
        certification_failure_reasons.append("stdout_mismatch")
    if not same_exit:
        certification_failure_reasons.append("exit_code_mismatch")
    if avm_exit_code != 0 and not budget_exceeded:
        certification_failure_reasons.append("sidecar_exit_nonzero")
    if not canonical_surface:
        certification_failure_reasons.append("missing_or_noncanonical_avm_gas_surface")
    elif not budget_exceeded and not canonical_positive_gas:
        certification_failure_reasons.append("missing_or_nonpositive_avm_gas")
    if available:
        certification_status = "stdout_exit_match"
        package_policy_may_use_reason = "stdout_exit_match_with_avm_canonical_gas"
        certification_failure_reasons = []
    elif package_policy_may_use and budget_exceeded:
        certification_status = "budget_exceeded_canonical_surface"
        package_policy_may_use_reason = "avm_canonical_gas_budget_exceeded"
        certification_failure_reasons = []
    else:
        certification_status = "unavailable"
        package_policy_may_use_reason = "sidecar_stdout_or_exit_mismatch_or_missing_canonical_gas"
    return {
        "schema": "oren.avm-canonical-sidecar-gas.v0",
        "status": "available" if available else ("budget_exceeded" if budget_exceeded else "unavailable"),
        "source": str(src),
        "native_backend": "native",
        "sidecar_backend": "obc",
        "sidecar_artifact": str(obc),
        "same_source": True,
        "same_run_stdout_equal": same_stdout,
        "same_run_exit_code_equal": same_exit,
        "native_stdout_sha256": sha256_s(native_stdout_normalized),
        "sidecar_stdout_sha256": sha256_s(avm_stdout_normalized),
        "native_stderr_sha256": sha256_s(native_stderr_normalized),
        "sidecar_stderr_sha256": sha256_s(avm_stderr_normalized),
        "certification_status": certification_status,
        "certification_failure_reasons": certification_failure_reasons,
        "gas_surface": avm_gas_surface,
        "gas_executed": avm_gas_used,
        "gas_remaining": avm_gas_remaining,
        "budget_exceeded": budget_exceeded,
        "budget_exceeded_source": budget_exceeded_source,
        "sidecar_error": avm_run_error,
        "native_runtime_conversion": False,
        "package_policy_may_use": package_policy_may_use,
        "package_policy_may_use_reason": package_policy_may_use_reason,
        "policy_scope": "native_package_policy_same_source_artifact",
        "reason": "package-bound AVM canonical sidecar gas; not a native runtime gas conversion",
    }

def child_cpu_ms_supported():
    return resource is not None and hasattr(resource, "RUSAGE_CHILDREN")

def child_cpu_ms_snapshot():
    if not child_cpu_ms_supported():
        return None
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    return int(round((usage.ru_utime + usage.ru_stime) * 1000.0))

def cpu_delta_ms(before, after):
    if before is None or after is None:
        return None
    return max(0, after - before)

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
obc_sidecar = tmp_dir / f"{stem}.sidecar.obc"
meta_out = tmp_dir / f"{stem}.metadata.json"
build_log = os.environ.get("OREN_NATIVE_PACKAGE_POLICY_BUILD_LOG", f"build/logs/native_package_policy_{stem}_{ts}.build.log")
run_json_path = os.environ.get("OREN_NATIVE_PACKAGE_POLICY_RUN_JSON", "")
requested_gas_enforcement_profile = normalize_gas_profile(os.environ.get("OREN_NATIVE_PACKAGE_POLICY_GAS_PROFILE"))
gas_enforcement_profile = requested_gas_enforcement_profile
avm_sidecar_env_requested = bool(os.environ.get("OREN_NATIVE_PACKAGE_POLICY_AVM_SIDECAR"))
avm_sidecar_enabled = avm_sidecar_env_requested
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

def run_summary_payload(*, exit_code, status, elapsed_ns, src, out, profile, caps, wall_ms, budgets, native_run_json=None, cpu_used_ms=None, avm_sidecar_gas=None):
    unsupported = []
    cap_domains = [d for d in caps.split(",") if d]
    native_summary = None
    if native_run_json:
        native_summary = native_run_json.get("effect_ledger_summary") or None
    heap_limit = budgets.get("heap_bytes")
    heap_used = native_heap_used_from_run_json(native_run_json)
    heap_enforced = heap_limit is not None and heap_used is not None
    heap_exceeded = bool(heap_enforced and heap_used > int(heap_limit))
    gas_limit = budgets.get("gas")
    gas_used, gas_remaining, gas_kind, gas_surface = native_gas_from_run_json(native_run_json)
    gas_surface_id = gas_surface.get("id") if isinstance(gas_surface, dict) else None
    native_gas_enforced = (
        gas_limit is not None
        and gas_enforcement_profile == "native-stmt"
        and gas_used is not None
        and gas_kind == NATIVE_GAS_KIND
        and gas_surface_id == NATIVE_GAS_KIND
    )
    sidecar_gas_used = None
    sidecar_gas_remaining = None
    sidecar_gas_kind = None
    sidecar_gas_surface = None
    sidecar_gas_surface_id = None
    sidecar_budget_exceeded = False
    if avm_sidecar_gas:
        sidecar_gas_used = avm_sidecar_gas.get("gas_executed")
        sidecar_gas_remaining = avm_sidecar_gas.get("gas_remaining")
        sidecar_gas_surface = avm_sidecar_gas.get("gas_surface")
        sidecar_gas_surface_id = sidecar_gas_surface.get("id") if isinstance(sidecar_gas_surface, dict) else None
        sidecar_gas_kind = sidecar_gas_surface_id
        sidecar_budget_exceeded = avm_sidecar_gas.get("budget_exceeded") is True or avm_sidecar_gas.get("status") == "budget_exceeded"
        try:
            if sidecar_gas_used is not None:
                sidecar_gas_used = int(sidecar_gas_used)
        except (TypeError, ValueError):
            sidecar_gas_used = None
    sidecar_gas_enforced = (
        gas_limit is not None
        and gas_enforcement_profile == "avm-sidecar"
        and avm_sidecar_gas is not None
        and avm_sidecar_gas.get("package_policy_may_use") is True
        and avm_sidecar_gas.get("certification_status") in ("stdout_exit_match", "budget_exceeded_canonical_surface")
        and sidecar_gas_surface_id == "avm_opcode_cost_v0"
    )
    if sidecar_gas_enforced:
        gas_used = sidecar_gas_used
        gas_remaining = sidecar_gas_remaining
        gas_kind = sidecar_gas_kind
        gas_surface = sidecar_gas_surface
    gas_enforced = native_gas_enforced or sidecar_gas_enforced
    gas_exceeded = bool(
        (native_gas_enforced and gas_used is not None and gas_used > int(gas_limit))
        or (sidecar_gas_enforced and sidecar_budget_exceeded)
        or (sidecar_gas_enforced and gas_used is not None and gas_used > int(gas_limit))
    )
    cpu_limit = budgets.get("cpu_ms")
    cpu_enforced = cpu_limit is not None and cpu_used_ms is not None
    cpu_exceeded = bool(cpu_enforced and cpu_used_ms > int(cpu_limit))
    # Stable runner budget_status vocabulary includes:
    # runner_wall_only, runner_wall_native_gas, runner_wall_avm_canonical_gas,
    # runner_wall_native_heap, runner_wall_child_cpu, plus combined forms such as
    # runner_wall_native_gas_native_heap_child_cpu.
    budget_parts = ["runner_wall"]
    if gas_enforced:
        budget_parts.append("avm_canonical_gas" if gas_enforcement_profile == "avm-sidecar" else "native_gas")
    if heap_enforced:
        budget_parts.append("native_heap")
    if cpu_enforced:
        budget_parts.append("child_cpu")
    if len(budget_parts) == 1:
        budget_status = "runner_wall_only"
    else:
        budget_status = "_".join(budget_parts)
    scope_parts = ["process-watchdog"]
    if native_summary is not None:
        scope_parts.append("native-run-json")
    if cpu_enforced:
        scope_parts.append("child-rusage")
    if avm_sidecar_gas and avm_sidecar_gas.get("package_policy_may_use") is True:
        scope_parts.append("avm-canonical-sidecar")
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
            "scope": "+".join(scope_parts),
            "budget_status": budget_status,
        },
        "avm_canonical_sidecar_gas": avm_sidecar_gas or {
            "schema": "oren.avm-canonical-sidecar-gas.v0",
            "status": "not_requested",
            "package_policy_may_use": False,
            "policy_scope": "native_package_policy_same_source_artifact",
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
                "limit": gas_limit,
                "executed": gas_used,
                "remaining": gas_remaining,
                "kind": gas_kind,
                "surface": gas_surface,
                "enforced": gas_enforced,
                "enforcement": (
                    "avm-canonical-sidecar"
                    if sidecar_gas_enforced
                    else ("native-run-json-stmt-loop-tick" if native_gas_enforced else "none")
                ),
                "enforcement_profile": gas_enforcement_profile,
                "requested_enforcement_profile": requested_gas_enforcement_profile,
                "exceeded": gas_exceeded,
                "reason": (
                    None
                    if gas_enforced or gas_limit is None
                    else (
                        "AVM canonical sidecar gas was not certified"
                        if gas_enforcement_profile == "avm-sidecar"
                        else "native statement+loop gas summary was not captured"
                    )
                ),
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
                "limit": cpu_limit,
                "used": cpu_used_ms,
                "enforced": cpu_enforced,
                "enforcement": "runner-child-rusage" if cpu_enforced else "none",
                "exceeded": cpu_exceeded,
                "reason": None if cpu_enforced or cpu_limit is None else "child process CPU usage is unavailable on this host",
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
    wall_ms = None
    gas_limit = None
    heap_limit = None
    cpu_limit = None
    if budgets.get("gas") is not None:
        gas_limit = positive_int(budgets.get("gas"), "budget_gas")
    if budgets.get("heap_bytes") is not None:
        heap_limit = positive_int(budgets.get("heap_bytes"), "budget_heap_bytes")
    if budgets.get("cpu_ms") is not None:
        cpu_limit = positive_int(budgets.get("cpu_ms"), "budget_cpu_ms")
        if not child_cpu_ms_supported():
            fail(
                "native package runner cannot enforce budget_cpu_ms on this host; "
                "use AVM package-policy execution or remove that declaration for native"
            )
    if budgets.get("wall_ms") is not None:
        wall_ms = positive_int(budgets.get("wall_ms"), "budget_wall_ms")
    env_wall = os.environ.get("OREN_NATIVE_PACKAGE_POLICY_TIMEOUT_MS")
    if env_wall:
        env_wall_i = positive_int(env_wall, "OREN_NATIVE_PACKAGE_POLICY_TIMEOUT_MS")
        wall_ms = env_wall_i if wall_ms is None else min(wall_ms, env_wall_i)
    if requested_gas_enforcement_profile == "auto":
        gas_enforcement_profile = "avm-sidecar" if gas_limit is not None else "native-stmt"
    avm_sidecar_enabled = avm_sidecar_env_requested or gas_enforcement_profile == "avm-sidecar"

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
    build_env = os.environ.copy()
    if gas_limit is not None and gas_enforcement_profile == "native-stmt":
        build_env["OREN_NATIVE_GAS_ACCOUNTING"] = "stmt"
    run_checked(build_cmd, env=build_env, log_path=build_log)

    if avm_sidecar_enabled:
        sidecar_build_log = f"build/logs/native_package_policy_{stem}_{ts}.avm-sidecar.build.log"
        run_checked(
            ["./oren", "build", src, "--backend", "bytecode", "--manifest", "-o", str(obc_sidecar)],
            log_path=sidecar_build_log,
        )

    env = os.environ.copy()
    env["OREN_CAPSULE"] = "1"
    env["OREN_CAP_ALLOW_DOMAINS"] = caps
    capture_native_run_json = bool(run_json_path or heap_limit is not None or gas_limit is not None or avm_sidecar_enabled)
    if capture_native_run_json:
        env["OREN_NATIVE_RUN_JSON"] = "1"
    if gas_limit is not None and gas_enforcement_profile == "native-stmt":
        env["OREN_NATIVE_GAS_ACCOUNTING"] = "stmt"
    timeout = None if wall_ms is None else wall_ms / 1000.0
    start_ns = time.monotonic_ns()
    cpu_before_ms = child_cpu_ms_snapshot() if cpu_limit is not None else None
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
            native_stdout = p.stdout or ""
            native_run_json = extract_native_run_json(native_stdout)
        else:
            p = subprocess.run([str(out), *prog_args], env=env, timeout=timeout)
            native_stdout = ""
            native_run_json = None
    except subprocess.TimeoutExpired:
        elapsed_ns = time.monotonic_ns() - start_ns
        cpu_used_ms = cpu_delta_ms(cpu_before_ms, child_cpu_ms_snapshot())
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
            cpu_used_ms=cpu_used_ms,
        ))
        fail(f"package native wall budget exceeded: {wall_ms}ms", rc=124)
    elapsed_ns = time.monotonic_ns() - start_ns
    cpu_used_ms = cpu_delta_ms(cpu_before_ms, child_cpu_ms_snapshot())
    avm_sidecar_gas = None
    if avm_sidecar_enabled and p.returncode == 0:
        avm_env = os.environ.copy()
        if profile == "capsule":
            avm_env["AVM_CAPSULE"] = "1"
            avm_env["AVM_ALLOW_DOMAINS"] = avm_allow_domains_for_package(pkg.get("cap_allow_domains") or [])
        if gas_limit is not None:
            avm_env["AVM_GAS"] = str(gas_limit)
        if heap_limit is not None:
            avm_env["AVM_MEM_BYTES"] = str(heap_limit)
        if wall_ms is not None:
            avm_env["AVM_TIMEOUT_MS"] = str(wall_ms)
        avm_cmd = ["./avm", "--print-run-json", str(obc_sidecar)]
        if prog_args:
            avm_cmd.extend(["--", *prog_args])
        try:
            avm_p = subprocess.run(
                avm_cmd,
                env=avm_env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            avm_sidecar_gas = {
                "schema": "oren.avm-canonical-sidecar-gas.v0",
                "status": "timeout",
                "source": str(src),
                "native_backend": "native",
                "sidecar_backend": "obc",
                "sidecar_artifact": str(obc_sidecar),
                "same_source": True,
                "native_runtime_conversion": False,
                "package_policy_may_use": False,
                "package_policy_may_use_reason": "avm_canonical_sidecar_timeout",
                "certification_status": "timeout",
                "certification_failure_reasons": ["timeout"],
                "policy_scope": "native_package_policy_same_source_artifact",
                "reason": "AVM canonical sidecar timed out under package wall budget",
            }
            write_run_json(run_summary_payload(
                exit_code=77,
                status="budget_unavailable",
                elapsed_ns=elapsed_ns,
                src=src,
                out=out,
                profile=profile,
                caps=caps,
                wall_ms=wall_ms,
                budgets=budgets,
                native_run_json=native_run_json,
                cpu_used_ms=cpu_used_ms,
                avm_sidecar_gas=avm_sidecar_gas,
            ))
            fail("package AVM canonical sidecar timed out", rc=77)
        avm_sidecar_gas = avm_canonical_sidecar_payload(
            src=src,
            obc=obc_sidecar,
            native_stdout=native_stdout,
            native_stderr=p.stderr or "",
            native_exit_code=p.returncode,
            avm_stdout=avm_p.stdout or "",
            avm_exit_code=avm_p.returncode,
            avm_run_json=extract_avm_run_json(avm_p.stdout or ""),
            avm_stderr=avm_p.stderr or "",
        )
        if gas_enforcement_profile == "avm-sidecar" and avm_sidecar_gas.get("status") == "budget_exceeded":
            write_run_json(run_summary_payload(
                exit_code=127,
                status="budget_exceeded",
                elapsed_ns=elapsed_ns,
                src=src,
                out=out,
                profile=profile,
                caps=caps,
                wall_ms=wall_ms,
                budgets=budgets,
                native_run_json=native_run_json,
                cpu_used_ms=cpu_used_ms,
                avm_sidecar_gas=avm_sidecar_gas,
            ))
            fail(f"package AVM canonical sidecar gas budget exceeded: limit {gas_limit}", rc=127)
        if avm_sidecar_gas.get("status") != "available":
            write_run_json(run_summary_payload(
                exit_code=77,
                status="budget_unavailable",
                elapsed_ns=elapsed_ns,
                src=src,
                out=out,
                profile=profile,
                caps=caps,
                wall_ms=wall_ms,
                budgets=budgets,
                native_run_json=native_run_json,
                cpu_used_ms=cpu_used_ms,
                avm_sidecar_gas=avm_sidecar_gas,
            ))
            fail("package AVM canonical sidecar gas could not be certified for native run", rc=77)
    if gas_limit is not None and gas_enforcement_profile == "avm-sidecar":
        if not avm_sidecar_gas or avm_sidecar_gas.get("package_policy_may_use") is not True:
            write_run_json(run_summary_payload(
                exit_code=77,
                status="budget_unavailable",
                elapsed_ns=elapsed_ns,
                src=src,
                out=out,
                profile=profile,
                caps=caps,
                wall_ms=wall_ms,
                budgets=budgets,
                native_run_json=native_run_json,
                cpu_used_ms=cpu_used_ms,
                avm_sidecar_gas=avm_sidecar_gas,
            ))
            fail("package AVM canonical sidecar gas was not certified for enforcement", rc=77)
    elif gas_limit is not None:
        gas_used, gas_remaining, gas_kind, gas_surface = native_gas_from_run_json(native_run_json)
        gas_surface_id = gas_surface.get("id") if isinstance(gas_surface, dict) else None
        if gas_used is None or gas_kind != NATIVE_GAS_KIND or gas_surface_id != NATIVE_GAS_KIND:
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
                cpu_used_ms=cpu_used_ms,
                avm_sidecar_gas=avm_sidecar_gas,
            ))
            fail("package native gas budget cannot be checked: native statement+loop gas summary was not captured", rc=76)
        if gas_used > gas_limit:
            write_run_json(run_summary_payload(
                exit_code=127,
                status="budget_exceeded",
                elapsed_ns=elapsed_ns,
                src=src,
                out=out,
                profile=profile,
                caps=caps,
                wall_ms=wall_ms,
                budgets=budgets,
                native_run_json=native_run_json,
                cpu_used_ms=cpu_used_ms,
                avm_sidecar_gas=avm_sidecar_gas,
            ))
            fail(f"package native gas budget exceeded: used {gas_used} {NATIVE_GAS_KIND} > limit {gas_limit}", rc=127)
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
                cpu_used_ms=cpu_used_ms,
                avm_sidecar_gas=avm_sidecar_gas,
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
                cpu_used_ms=cpu_used_ms,
                avm_sidecar_gas=avm_sidecar_gas,
            ))
            fail(f"package native heap budget exceeded: used {heap_used} bytes > limit {heap_limit} bytes", rc=125)
    if cpu_limit is not None:
        if cpu_used_ms is None:
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
                cpu_used_ms=cpu_used_ms,
                avm_sidecar_gas=avm_sidecar_gas,
            ))
            fail("package native CPU budget cannot be checked: child process CPU usage is unavailable", rc=76)
        if cpu_used_ms > cpu_limit:
            write_run_json(run_summary_payload(
                exit_code=126,
                status="budget_exceeded",
                elapsed_ns=elapsed_ns,
                src=src,
                out=out,
                profile=profile,
                caps=caps,
                wall_ms=wall_ms,
                budgets=budgets,
                native_run_json=native_run_json,
                cpu_used_ms=cpu_used_ms,
                avm_sidecar_gas=avm_sidecar_gas,
            ))
            fail(f"package native CPU budget exceeded: used {cpu_used_ms}ms > limit {cpu_limit}ms", rc=126)
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
        cpu_used_ms=cpu_used_ms,
        avm_sidecar_gas=avm_sidecar_gas,
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
