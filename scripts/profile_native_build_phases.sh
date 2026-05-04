#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

compiler="${OREN_PROFILE_NATIVE_COMPILER:-./oren_stage2}"
src="${1:-${OREN_PROFILE_NATIVE_SRC:-tests/fixtures/generator_surface_v0.oren}}"
platform="${OREN_PLATFORM:-arm64-macos}"
ts="${OREN_PROFILE_NATIVE_TS:-$(date +%Y%m%d_%H%M%S)}"
out="${OREN_PROFILE_NATIVE_OUT:-build/tmp/native_build_phase_profile_${ts}.native}"
log="${OREN_PROFILE_NATIVE_LOG:-build/logs/native_build_phase_profile_${ts}.log}"
phase_log="${OREN_PROFILE_NATIVE_PHASE_LOG:-build/logs/native_build_phase_profile_${ts}.phases.log}"
function_log="${OREN_PROFILE_NATIVE_FUNCTION_LOG:-build/logs/native_build_phase_profile_${ts}.functions.log}"
stmt_log="${OREN_PROFILE_NATIVE_STMT_LOG:-build/logs/native_build_phase_profile_${ts}.stmts.log}"
timeout_secs="${OREN_PROFILE_NATIVE_TIMEOUT_SECS:-180}"

mkdir -p "$(dirname "$out")" "$(dirname "$log")" "$(dirname "$phase_log")" "$(dirname "$function_log")" "$(dirname "$stmt_log")"

echo "== native build phase profile =="
echo "compiler=$compiler"
echo "src=$src"
echo "platform=$platform"
echo "log=$log"
echo "phase_log=$phase_log"
echo "function_log=$function_log"
if [[ "${OREN_PROFILE_NATIVE_STMTS:-0}" != "0" ]]; then
  echo "stmt_log=$stmt_log"
fi
if [[ "${OREN_PROFILE_MACHO_RESOLVE_STATS:-0}" != "0" ]]; then
  echo "macho_resolve_stats=1"
fi

if [[ ! -x "$compiler" ]]; then
  echo "ERROR: missing executable compiler: $compiler" >&2
  echo "Hint: run make stage2 or set OREN_PROFILE_NATIVE_COMPILER." >&2
  exit 2
fi
if [[ ! -f "$src" ]]; then
  echo "ERROR: missing source: $src" >&2
  exit 2
fi

source scripts/verify_parallel_jobs.sh

native_astbin_seed="$(verify_native_astbin_seed_path "$platform" "$log" || true)"
if [[ -n "$native_astbin_seed" ]]; then
  echo "native_runtime_astbin_seed=$native_astbin_seed" >>"$log"
fi
verify_native_rtobj_seed_prewarm "$platform" "$log" "$compiler" || true

start_s="$(date +%s)"
: >"$function_log"
export OREN_TRACE_BUILD_PHASES_PATH="$phase_log"
export OREN_TRACE_ARM64_FUNCTIONS_PATH="$function_log"
if [[ "${OREN_PROFILE_NATIVE_STMTS:-0}" != "0" ]]; then
  : >"$stmt_log"
  export OREN_TRACE_ARM64_STMTS_PATH="$stmt_log"
fi
if [[ "${OREN_PROFILE_MACHO_RESOLVE_STATS:-0}" != "0" ]]; then
  export OREN_TRACE_MACHO_LOCAL_RESOLVE_STATS=1
fi
if ! run_native_build_timeout_logged "$timeout_secs" "$compiler" build "$src" \
  --backend native --platform "$platform" --no-cache --no-debug -o "$out" >>"$log" 2>&1; then
  echo "ERROR: native build failed; see $log" >&2
  exit 1
fi
end_s="$(date +%s)"
echo "real $((end_s - start_s))" >>"$log"

python3 - "$phase_log" "$function_log" "$stmt_log" <<'PY'
import re
import sys
from pathlib import Path

phase_log = Path(sys.argv[1])
function_log = Path(sys.argv[2])
stmt_log = Path(sys.argv[3])
phase_re = re.compile(r"phase=([^ ]+) now_ns=([0-9]+)(.*)$")
fn_re = re.compile(r"fn=(.*?) phase=([^ ]*) ms=([0-9]+) bytes=([0-9]+)$")
stmt_re = re.compile(r"stmt=([^ ]*) phase=([^ ]*) fn=([^ ]*) count=([0-9]+) ms=([0-9]+) bytes=([0-9]+)$")

events = []
for line in phase_log.read_text(errors="replace").splitlines():
    match = phase_re.search(line)
    if not match:
        continue
    events.append((match.group(1), int(match.group(2)), match.group(3).strip()))

if len(events) < 2:
    print("WARNING: insufficient phase data")
    raise SystemExit(0)

print("== adjacent phase deltas ==")
deltas = []
for idx in range(1, len(events)):
    prev_name, prev_ns, _ = events[idx - 1]
    name, ns, detail = events[idx]
    ms = (ns - prev_ns) / 1_000_000
    deltas.append((ms, prev_name, name, detail))
for ms, prev_name, name, detail in deltas:
    suffix = f" {detail}" if detail else ""
    print(f"{ms:10.3f} ms  {prev_name} -> {name}{suffix}")

print("== top adjacent phase deltas ==")
for ms, prev_name, name, detail in sorted(deltas, reverse=True)[:15]:
    suffix = f" {detail}" if detail else ""
    print(f"{ms:10.3f} ms  {prev_name} -> {name}{suffix}")

rows = []
if function_log.exists():
    for line in function_log.read_text(errors="replace").splitlines():
        match = fn_re.search(line)
        if not match:
            continue
        rows.append({
            "name": match.group(1),
            "phase": match.group(2),
            "ms": int(match.group(3)),
            "bytes": int(match.group(4)),
        })

if not rows:
    print("WARNING: no ARM64 function profile data")
    raise SystemExit(0)

print("== function codegen by phase ==")
by_phase = {}
for row in rows:
    phase = row["phase"]
    agg = by_phase.setdefault(phase, {"count": 0, "ms": 0, "bytes": 0})
    agg["count"] += 1
    agg["ms"] += row["ms"]
    agg["bytes"] += row["bytes"]
for phase, agg in sorted(by_phase.items(), key=lambda item: (item[1]["ms"], item[1]["bytes"]), reverse=True):
    print(f"{agg['ms']:10d} ms  {agg['bytes']:10d} bytes  {agg['count']:5d} funcs  phase={phase}")

print("== top function codegen bodies ==")
for row in sorted(rows, key=lambda item: (item["ms"], item["bytes"]), reverse=True)[:25]:
    print(f"{row['ms']:10d} ms  {row['bytes']:10d} bytes  phase={row['phase']} fn={row['name']}")

stmt_rows = []
if stmt_log.exists() and stmt_log.stat().st_size > 0:
    for line in stmt_log.read_text(errors="replace").splitlines():
        match = stmt_re.search(line)
        if not match:
            continue
        stmt_rows.append({
            "stmt": match.group(1),
            "phase": match.group(2),
            "fn": match.group(3),
            "count": int(match.group(4)),
            "ms": int(match.group(5)),
            "bytes": int(match.group(6)),
        })

if stmt_rows:
    print("== inclusive statement codegen by phase/type ==")
    by_phase_type = {}
    for row in stmt_rows:
        key = (row["phase"], row["stmt"])
        agg = by_phase_type.setdefault(key, {"count": 0, "ms": 0, "bytes": 0})
        agg["count"] += row["count"]
        agg["ms"] += row["ms"]
        agg["bytes"] += row["bytes"]
    for (phase, stmt), agg in sorted(by_phase_type.items(), key=lambda item: (item[1]["ms"], item[1]["bytes"], item[1]["count"]), reverse=True)[:30]:
        print(f"{agg['ms']:10d} ms  {agg['bytes']:10d} bytes  {agg['count']:6d} stmts  phase={phase} stmt={stmt}")

    function_decl_rows = [row for row in stmt_rows if row["stmt"].startswith("FunctionDecl(")]
    if function_decl_rows:
        print("== function declaration subphases by phase/type ==")
        by_function_decl = {}
        for row in function_decl_rows:
            key = (row["phase"], row["stmt"])
            agg = by_function_decl.setdefault(key, {"count": 0, "ms": 0, "bytes": 0})
            agg["count"] += row["count"]
            agg["ms"] += row["ms"]
            agg["bytes"] += row["bytes"]
        for (phase, stmt), agg in sorted(by_function_decl.items(), key=lambda item: (item[1]["ms"], item[1]["bytes"], item[1]["count"]), reverse=True)[:30]:
            print(f"{agg['ms']:10d} ms  {agg['bytes']:10d} bytes  {agg['count']:6d} funcs  phase={phase} stmt={stmt}")

    if_stmt_rows = [row for row in stmt_rows if row["stmt"].startswith("IfStmt(")]
    if if_stmt_rows:
        print("== if statement subphases by phase/type ==")
        by_if_stmt = {}
        for row in if_stmt_rows:
            key = (row["phase"], row["stmt"])
            agg = by_if_stmt.setdefault(key, {"count": 0, "ms": 0, "bytes": 0})
            agg["count"] += row["count"]
            agg["ms"] += row["ms"]
            agg["bytes"] += row["bytes"]
        for (phase, stmt), agg in sorted(by_if_stmt.items(), key=lambda item: (item[1]["ms"], item[1]["bytes"], item[1]["count"]), reverse=True)[:30]:
            print(f"{agg['ms']:10d} ms  {agg['bytes']:10d} bytes  {agg['count']:6d} stmts  phase={phase} stmt={stmt}")

    cond_term_rows = [row for row in stmt_rows if row["stmt"].startswith("CondTerm(")]
    if cond_term_rows:
        print("== condition term lowering by phase/type ==")
        by_cond_term = {}
        for row in cond_term_rows:
            key = (row["phase"], row["stmt"])
            agg = by_cond_term.setdefault(key, {"count": 0, "ms": 0, "bytes": 0})
            agg["count"] += row["count"]
            agg["ms"] += row["ms"]
            agg["bytes"] += row["bytes"]
        for (phase, stmt), agg in sorted(by_cond_term.items(), key=lambda item: (item[1]["ms"], item[1]["bytes"], item[1]["count"]), reverse=True)[:40]:
            print(f"{agg['ms']:10d} ms  {agg['bytes']:10d} bytes  {agg['count']:6d} terms  phase={phase} stmt={stmt}")

    map_str_rows = [row for row in stmt_rows if row["stmt"].startswith("MapStrIndex(")]
    if map_str_rows:
        print("== map string-literal index subphases by phase/type ==")
        by_map_str = {}
        for row in map_str_rows:
            key = (row["phase"], row["stmt"])
            agg = by_map_str.setdefault(key, {"count": 0, "ms": 0, "bytes": 0})
            agg["count"] += row["count"]
            agg["ms"] += row["ms"]
            agg["bytes"] += row["bytes"]
        for (phase, stmt), agg in sorted(by_map_str.items(), key=lambda item: (item[1]["ms"], item[1]["bytes"], item[1]["count"]), reverse=True)[:30]:
            print(f"{agg['ms']:10d} ms  {agg['bytes']:10d} bytes  {agg['count']:6d} exprs  phase={phase} stmt={stmt}")

    call_expr_rows = [row for row in stmt_rows if row["stmt"].startswith("CallExpr(")]
    if call_expr_rows:
        print("== call expression lowering by phase/type ==")
        by_call_expr = {}
        for row in call_expr_rows:
            key = (row["phase"], row["stmt"])
            agg = by_call_expr.setdefault(key, {"count": 0, "ms": 0, "bytes": 0})
            agg["count"] += row["count"]
            agg["ms"] += row["ms"]
            agg["bytes"] += row["bytes"]
        for (phase, stmt), agg in sorted(by_call_expr.items(), key=lambda item: (item[1]["ms"], item[1]["bytes"], item[1]["count"]), reverse=True)[:40]:
            print(f"{agg['ms']:10d} ms  {agg['bytes']:10d} bytes  {agg['count']:6d} calls  phase={phase} stmt={stmt}")

    print("== top inclusive statement codegen function/type buckets ==")
    for row in sorted(stmt_rows, key=lambda item: (item["ms"], item["bytes"], item["count"]), reverse=True)[:40]:
        print(f"{row['ms']:10d} ms  {row['bytes']:10d} bytes  {row['count']:6d} stmts  phase={row['phase']} fn={row['fn']} stmt={row['stmt']}")
PY
