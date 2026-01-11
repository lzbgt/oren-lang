#!/usr/bin/env bash
set -euo pipefail

# Bounded triage helper for: "stage2 native compile is slow / feels hung".
#
# This intentionally runs only a few high-signal checks, all bounded:
# - rtobj miss->hit benchmark (compile one file)
# - perf guard on the rtobj-hit time budget
# - optional x64-linux runtime smoke under QEMU (if requested)
#
# The goal is to provide a single command that produces *actionable* output without huge logs.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DO_QEMU=0
TIMEOUT_SECS="${OREN_NATIVE_BUILD_TIMEOUT_SECS:-60}"
HIT_MAX_MS="${OREN_NATIVE_HIT_MAX_MS:-4000}"

usage() {
  cat <<'EOF'
Usage:
  scripts/triage_native_slow_compile.sh [--qemu] [--timeout-secs N] [--hit-max-ms N]

Examples:
  ./scripts/triage_native_slow_compile.sh
  ./scripts/triage_native_slow_compile.sh --timeout-secs 120 --hit-max-ms 4500
  ./scripts/triage_native_slow_compile.sh --qemu

Notes:
  - Uses `./scripts/bench_native_compile_one_file.sh` and `./scripts/perf_guard_native_compile_one_file_hit.sh`.
  - `--qemu` runs `make verify-x64-linux-qemu` (requires the existing linux container `c7e5f7bd9f5c`).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --qemu)
      DO_QEMU=1
      shift
      ;;
    --timeout-secs)
      TIMEOUT_SECS="${2:-}"
      shift 2
      ;;
    --hit-max-ms)
      HIT_MAX_MS="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

echo "== triage: native slow compile ==" >&2
echo "timeout_secs=$TIMEOUT_SECS hit_max_ms=$HIT_MAX_MS qemu=$DO_QEMU" >&2

echo "" >&2
echo "== 1) bench: compile one file (rtobj miss -> hit) ==" >&2
OREN_NATIVE_BUILD_TIMEOUT_SECS="$TIMEOUT_SECS" ./scripts/bench_native_compile_one_file.sh --no-debug

echo "" >&2
echo "== 2) perf guard: rtobj hit under threshold ==" >&2
OREN_NATIVE_BUILD_TIMEOUT_SECS="$TIMEOUT_SECS" OREN_NATIVE_HIT_MAX_MS="$HIT_MAX_MS" \
  ./scripts/perf_guard_native_compile_one_file_hit.sh

if [[ "$DO_QEMU" -ne 0 ]]; then
  echo "" >&2
  echo "== 3) x64-linux runtime smoke under qemu (stage1+stage2) ==" >&2
  make verify-x64-linux-qemu
fi

echo "" >&2
echo "OK: triage complete" >&2

