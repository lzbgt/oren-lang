#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/analyze_stage2_failure_log.sh <log_path> [--max N] [--tail N]

Purpose:
  Produce a bounded, high-signal summary for a stage2 self-host / native-backend build log
  (especially x64-windows / x64-linux remote logs) without dumping thousands of lines.

Defaults:
  --max  60   (max lines per section)
  --tail 120  (tail lines from end of log)

Notes:
  - This script intentionally uses only POSIX-ish tools (`grep`, `sed`, `tail`, `wc`) so it
    runs on macOS/Linux shells. It does not require ripgrep.
  - For remote Win11 logs, first fetch the file into the repo (see `scripts/fetch_remote_file.sh`).
EOF
}

max_lines=60
tail_lines=120

log_path=""

# Accept `--help` without requiring a log path.
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# Parse args in any order: options can appear before or after the log path.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max)
      shift
      max_lines="${1:-}"
      ;;
    --tail)
      shift
      tail_lines="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "ERROR: unknown flag: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ "$log_path" == "" ]]; then
        log_path="$1"
      else
        echo "ERROR: unexpected extra arg: $1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
  shift || true
done

if [[ "$log_path" == "" ]]; then
  echo "ERROR: missing <log_path>" >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$log_path" ]]; then
  echo "ERROR: log not found: $log_path" >&2
  exit 2
fi

lines="$(wc -l <"$log_path" | tr -d ' ')"
bytes="$(wc -c <"$log_path" | tr -d ' ')"

echo "== stage2 log analysis (bounded) =="
echo "log=$log_path"
echo "size_bytes=$bytes lines=$lines"
echo "max_lines=$max_lines tail_lines=$tail_lines"
echo ""

section() {
  echo "== $1 =="
}

bounded_grep() {
  local label="$1"
  local pattern="$2"
  section "$label"
  # Prefer `grep -nE` for portability; if no matches, print a clean marker.
  if grep -nE "$pattern" "$log_path" >/dev/null 2>&1; then
    grep -nE "$pattern" "$log_path" | sed -n "1,${max_lines}p"
    local total
    total="$(grep -nE "$pattern" "$log_path" | wc -l | tr -d ' ')"
    if [[ "$total" -gt "$max_lines" ]]; then
      echo "(truncated: $total matches; showing first $max_lines)"
    else
      echo "(matches: $total)"
    fi
  else
    echo "(no matches)"
  fi
  echo ""
}

section "tail"
tail -n "$tail_lines" "$log_path" || true
echo ""

# High-signal error formats used by the compiler.
bounded_grep "OREN_DIAG" "OREN_DIAG|\\btypecheck:\\b|\\bNil-compare guard errors:\\b"

# Common failure indicators across shells/platforms.
bounded_grep "hard failures" "SIG(SEGV|ABRT)|segmentation fault|stack trace|\\bpanic\\b|\\bASSERT\\b|\\babort\\b|\\bfatal\\b|\\bFAIL\\b|\\bERROR\\b"

# Known x64 bring-up hazard the repo treats as a hard gate.
bounded_grep "x64 ABI arg-reg warnings" "x64 native v0: missing ABI arg reg"

# Timeout hints (build steps and runtime steps).
bounded_grep "timeouts" "timed out|timeout|ETIMEDOUT"

# Perf breadcrumbs (when enabled).
bounded_grep "phase timings" "\\[phase\\]|\\[trace\\] pass:|rtobj|astbin"

echo "== next actions (suggested) =="
echo "- If this is a remote Win11/WSL2 log, also capture:"
echo "  - remote host + OS build"
echo "  - compiler SHA (`git rev-parse HEAD`) on both sides"
echo "  - the exact failing command line"
echo "- If you see `x64 native v0: missing ABI arg reg`, treat it as a backend bug (not a flaky test)."
echo "- If the log is huge, rerun with smaller output: --max 30 --tail 80"
