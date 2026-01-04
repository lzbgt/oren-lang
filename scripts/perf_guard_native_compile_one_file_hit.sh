#!/usr/bin/env bash
set -euo pipefail

# Rolling performance guard (bounded):
# - verifies stage2-native "compile one file" rtobj HIT stays under a target threshold
# - does NOT gate rtobj MISS, because cold-path work is still actively being optimized
#
# This is intended as a lightweight regression tripwire for the most user-visible invariant:
#   "a simple file compilation should not be > ~4s on the primary dev host (rtobj hit)".
#
# Usage:
#   ./scripts/perf_guard_native_compile_one_file_hit.sh
#   OREN_NATIVE_HIT_MAX_MS=4500 ./scripts/perf_guard_native_compile_one_file_hit.sh
#
# Notes:
# - Uses the existing benchmark script which isolates the rtobj cache and runs miss->hit.
# - Parses the second run's `elapsed_ms=...` line and compares against threshold.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

HIT_MAX_MS="${OREN_NATIVE_HIT_MAX_MS:-4000}"
TIMEOUT_SECS="${OREN_NATIVE_BUILD_TIMEOUT_SECS:-60}"

need_bin() {
  local b="$1"
  if ! command -v "$b" >/dev/null 2>&1; then
    echo "ERROR: missing required tool in PATH: $b" >&2
    exit 2
  fi
}

need_bin awk

tmp_log="$(mktemp -t oren_perf_guard.XXXXXX)"
trap 'rm -f "$tmp_log" 2>/dev/null || true' EXIT

echo "== perf guard: native compile-one-file (rtobj hit) ==" >&2
echo "hit_max_ms=$HIT_MAX_MS timeout_secs=$TIMEOUT_SECS" >&2

set +e
OREN_NATIVE_BUILD_TIMEOUT_SECS="$TIMEOUT_SECS" ./scripts/bench_native_compile_one_file.sh --no-debug >"$tmp_log" 2>&1
rc=$?
set -e
if [[ "$rc" -ne 0 ]]; then
  tail -n 40 "$tmp_log" >&2
  echo "ERROR: benchmark failed (rc=$rc)" >&2
  exit "$rc"
fi

# Extract second run's elapsed_ms (the hit). The bench script prints:
#   elapsed_ms=<n>
# twice; we want the 2nd.
hit_ms="$(
  awk -F= '/^elapsed_ms=/ { v=$2; n++ } END { if (n>=2) print v; }' "$tmp_log"
)"

if [[ -z "$hit_ms" ]]; then
  tail -n 80 "$tmp_log" >&2
  echo "ERROR: failed to parse rtobj-hit elapsed_ms from benchmark output" >&2
  exit 2
fi

echo "hit_elapsed_ms=$hit_ms" >&2

if [[ "$hit_ms" -gt "$HIT_MAX_MS" ]]; then
  echo "ERROR: rtobj-hit compile-one-file exceeded threshold: hit_ms=$hit_ms > hit_max_ms=$HIT_MAX_MS" >&2
  echo "Hint: rerun with bounded tracing to localize the regression:" >&2
  echo "  OREN_TRACE_BUILD_SUMMARY=1 OREN_TRACE_RUNTIME_BUNDLE=1 OREN_TRACE_ASTBIN=1 OREN_TRACE_RUNTIME_OBJ_CACHE=1 \\" >&2
  echo "    OREN_NATIVE_BUILD_TIMEOUT_SECS=$TIMEOUT_SECS ./scripts/bench_native_compile_one_file.sh --no-debug" >&2
  exit 1
fi

echo "OK: rtobj-hit compile-one-file within threshold" >&2

