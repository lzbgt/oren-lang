#!/usr/bin/env bash
set -euo pipefail

runs="${1:-3}"
compiler="${2:-./oren_stage2}"
shift $(( $# > 0 ? 1 : 0 )) || true
shift $(( $# > 0 ? 1 : 0 )) || true

if ! [[ "$runs" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 [runs] [compiler] [ENV=VAL ...]"
  exit 2
fi

if [[ ! -x "$compiler" ]]; then
  echo "Compiler not found or not executable: $compiler"
  exit 2
fi

stage2_runs="${OREN_RUNTIME_ROBUSTNESS_STAGE2_RUNS:-1}"
c_runs="${OREN_RUNTIME_ROBUSTNESS_C_RUNS:-$runs}"
fixtures="${OREN_RUNTIME_ROBUSTNESS_C_FIXTURES:-tests/native/fixtures/arith_div0.oren,tests/native/fixtures/arith_div_overflow.oren,tests/native/fixtures/index_set_negative.oren}"

# Optional runtime tracing knobs (forwarded to child scripts).
# Example: OREN_RUNTIME_ROBUSTNESS_TRACE_ENV='OREN_TRACE_LIST_HDR_RING=1 OREN_TRACE_LIST_HDR_RING_PTR_GUARD=1'
trace_env="${OREN_RUNTIME_ROBUSTNESS_TRACE_ENV:-}"
trace_env_arr=()
if [[ -n "$trace_env" ]]; then
  # shellcheck disable=SC2206
  trace_env_arr=($trace_env)
fi

mkdir -p build/logs

ts="$(date +%Y%m%d_%H%M%S)"
log="build/logs/runtime_robustness_w5_${ts}.log"
uname_out="$(uname -a)"
git_rev="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

{
  echo "ts=$ts"
  echo "runs=$runs"
  echo "stage2_runs=$stage2_runs"
  echo "c_runs=$c_runs"
  echo "compiler=$compiler"
  echo "cwd=$(pwd)"
  echo "uname=$uname_out"
  echo "git_rev=$git_rev"
  echo "fixtures=$fixtures"
  echo "trace_env=$trace_env"
} >"$log"

IFS=',' read -r -a fixture_arr <<< "$fixtures"

if [[ "$stage2_runs" =~ ^[0-9]+$ ]] && [[ "$stage2_runs" -gt 0 ]]; then
  echo "== stage2 native quick integration (runs=$stage2_runs) ==" | tee -a "$log"
  ./scripts/triage_native_quick_stage2_flake_debug.sh "$stage2_runs" "$compiler" \
    "${trace_env_arr[@]}" "$@" \
    >>"$log" 2>&1
fi

for fixture in "${fixture_arr[@]}"; do
  if [[ -z "$fixture" ]]; then
    continue
  fi
  echo "== C backend build flake (runs=$c_runs, src=$fixture) ==" | tee -a "$log"
  OREN_TRACE_ARITH_SRC="$fixture" \
    ./scripts/triage_arith_div0_c_build_flake.sh "$c_runs" "$compiler" \
      "${trace_env_arr[@]}" "$@" \
      >>"$log" 2>&1
done

echo "OK: runtime robustness W5 checks passed (log=$log)" >&2
