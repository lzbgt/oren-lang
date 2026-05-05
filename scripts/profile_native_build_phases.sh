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

parse_module_rows = []
detail_field_re = re.compile(r"([a-zA-Z0-9_]+)=([^ ]*)")
for phase_name, _ns, detail in events:
    if phase_name != "link.parse_module.done":
        continue
    fields = {m.group(1): m.group(2) for m in detail_field_re.finditer(detail)}
    try:
        ms = int(fields.get("total_ms", "0"))
    except ValueError:
        ms = 0
    try:
        stmts = int(fields.get("stmts", "0"))
    except ValueError:
        stmts = 0
    try:
        traits = int(fields.get("traits", "0"))
    except ValueError:
        traits = 0
    sub_ms = {}
    for key in (
        "read_ms",
        "cache_ms",
        "parse_ms",
        "lexer_ms",
        "parser_ms",
        "parse_body_ms",
        "parse_prefix_ms",
        "parse_stmt_ms",
        "parse_lower_ms",
        "parse_yield_validate_ms",
        "parse_advance_ms",
        "parse_hot1_ms",
        "parse_hot2_ms",
        "parse_hot3_ms",
        "gen_scan_ms",
        "gen_core_ms",
        "gen_core_src_ms",
        "gen_core_lexer_ms",
        "gen_core_parser_ms",
        "forin_bridge_ms",
        "prepend_ms",
        "merge_ms",
        "prepare_ms",
    ):
        try:
            sub_ms[key] = int(fields.get(key, "0"))
        except ValueError:
            sub_ms[key] = 0
    parse_module_rows.append({
        "path": fields.get("path", ""),
        "ms": ms,
        "stmts": stmts,
        "traits": traits,
        "cache_hit": fields.get("cache_hit", "0"),
        "parse_hot1_label": fields.get("parse_hot1_label", ""),
        "parse_hot2_label": fields.get("parse_hot2_label", ""),
        "parse_hot3_label": fields.get("parse_hot3_label", ""),
        **sub_ms,
    })

if parse_module_rows:
    print("== module parse by path ==")
    def hot_label(row, idx):
        label = row[f"parse_hot{idx}_label"]
        ms = row[f"parse_hot{idx}_ms"]
        if not label:
            return f":{ms}"
        if ":ms=" in label:
            return label
        return f"{label}:{ms}"

    for row in sorted(parse_module_rows, key=lambda item: (item["ms"], item["stmts"], item["traits"]), reverse=True)[:30]:
        print(
            f"{row['ms']:10d} ms  {row['stmts']:6d} stmts  {row['traits']:5d} traits"
            f"  read={row['read_ms']:5d} cache={row['cache_ms']:5d} parse={row['parse_ms']:5d}"
            f" lexer={row['lexer_ms']:5d} parser={row['parser_ms']:5d}"
            f" body={row['parse_body_ms']:5d} stmt={row['parse_stmt_ms']:5d}"
            f" prefix={row['parse_prefix_ms']:5d} lower={row['parse_lower_ms']:5d}"
            f" yield={row['parse_yield_validate_ms']:5d} advance={row['parse_advance_ms']:5d}"
            f" gen_scan={row['gen_scan_ms']:5d}"
            f" gen_core={row['gen_core_ms']:5d} gen_src={row['gen_core_src_ms']:5d}"
            f" gen_lexer={row['gen_core_lexer_ms']:5d} gen_parser={row['gen_core_parser_ms']:5d}"
            f" forin_bridge={row['forin_bridge_ms']:5d} prepend={row['prepend_ms']:5d}"
            f" merge={row['merge_ms']:5d} prepare={row['prepare_ms']:5d}"
            f" hot1={hot_label(row, 1)}"
            f" hot2={hot_label(row, 2)}"
            f" hot3={hot_label(row, 3)}"
            f"  cache_hit={row['cache_hit']}  path={row['path']}"
        )

optimizer_hot_rows = []
optimizer_subphase_rows = []
for phase_name, _ns, detail in events:
    if phase_name != "optimizer.hot" and phase_name != "optimizer.summary":
        continue
    fields = {m.group(1): m.group(2) for m in detail_field_re.finditer(detail)}
    if "pass" in fields:
        try:
            ms = int(fields.get("ms", "0"))
        except ValueError:
            ms = 0
        try:
            rank = int(fields.get("rank", "0"))
        except ValueError:
            rank = 0
        optimizer_hot_rows.append({
            "pass": fields.get("pass", ""),
            "rank": rank,
            "fn": fields.get("fn", ""),
            "ms": ms,
        })
        continue
    for pass_name in ("fold", "list_int", "reserve"):
        for rank in (1, 2, 3):
            fn = fields.get(f"{pass_name}{rank}_fn", "")
            if not fn:
                continue
            try:
                ms = int(fields.get(f"{pass_name}{rank}_ms", "0"))
            except ValueError:
                ms = 0
            optimizer_hot_rows.append({
                "pass": pass_name,
                "rank": rank,
                "fn": fn,
                "ms": ms,
            })
    if phase_name == "optimizer.summary":
        sub = {"phase": "optimizer.summary"}
        for key in (
            "list_int_locals_ms",
            "list_int_nested_ms",
            "list_int_scan_ms2",
            "list_int_rewrite_init_ms",
            "list_int_rewrite_uses_ms",
            "reserve_track_ms",
            "reserve_collect_ms",
            "reserve_insert_ms",
            "reserve_rewrite_ms",
            "reserve_recurse_ms",
            "reserve_safe_ms",
        ):
            try:
                sub[key] = int(fields.get(key, "0"))
            except ValueError:
                sub[key] = 0
        optimizer_subphase_rows.append(sub)

if optimizer_hot_rows:
    print("== optimizer hot function bodies by pass ==")
    for row in sorted(optimizer_hot_rows, key=lambda item: (item["pass"], item["rank"])):
        print(f"{row['ms']:10d} ms  pass={row['pass']} rank={row['rank']} fn={row['fn']}")

if optimizer_subphase_rows:
    print("== optimizer list pass internals ==")
    for row in optimizer_subphase_rows:
        print(
            f"list_int locals={row['list_int_locals_ms']:5d}"
            f" nested={row['list_int_nested_ms']:5d}"
            f" scan={row['list_int_scan_ms2']:5d}"
            f" rewrite_init={row['list_int_rewrite_init_ms']:5d}"
            f" rewrite_uses={row['list_int_rewrite_uses_ms']:5d}"
            f" | reserve track={row['reserve_track_ms']:5d}"
            f" collect={row['reserve_collect_ms']:5d}"
            f" insert={row['reserve_insert_ms']:5d}"
            f" rewrite={row['reserve_rewrite_ms']:5d}"
            f" recurse={row['reserve_recurse_ms']:5d}"
            f" safe={row['reserve_safe_ms']:5d}"
        )

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

    call_generic_sub_rows = [row for row in stmt_rows if row["stmt"].startswith("CallGenericSub(")]
    if call_generic_sub_rows:
        print("== generic call subphases by phase/type ==")
        by_call_generic_sub = {}
        for row in call_generic_sub_rows:
            key = (row["phase"], row["stmt"])
            agg = by_call_generic_sub.setdefault(key, {"count": 0, "ms": 0, "bytes": 0})
            agg["count"] += row["count"]
            agg["ms"] += row["ms"]
            agg["bytes"] += row["bytes"]
        for (phase, stmt), agg in sorted(by_call_generic_sub.items(), key=lambda item: (item[1]["ms"], item[1]["bytes"], item[1]["count"]), reverse=True)[:60]:
            print(f"{agg['ms']:10d} ms  {agg['bytes']:10d} bytes  {agg['count']:6d} calls  phase={phase} stmt={stmt}")

    print("== top inclusive statement codegen function/type buckets ==")
    for row in sorted(stmt_rows, key=lambda item: (item["ms"], item["bytes"], item["count"]), reverse=True)[:40]:
        print(f"{row['ms']:10d} ms  {row['bytes']:10d} bytes  {row['count']:6d} stmts  phase={row['phase']} fn={row['fn']} stmt={row['stmt']}")
PY
