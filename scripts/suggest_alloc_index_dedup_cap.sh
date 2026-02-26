#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/suggest_alloc_index_dedup_cap.sh [--run] [log_path]

Options:
  --run    Run GC-stress quick integration with alloc-index tracing enabled,
           then parse the resulting log.

If log_path is omitted, the script uses:
  build/logs/oren_stage2_native_quick_integration.log

Environment:
  DEDUP_CAP_MULT  Multiplier for suggested cap (default: 4).
EOF
}

run_gc_stress() {
  OREN_TRACE_ALLOC_INDEX=1 make test-native-quick-gc-stress-stage2
}

main() {
  local run=0
  local log_path=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --run)
        run=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        if [[ -z "$log_path" ]]; then
          log_path="$1"
        else
          echo "error: unexpected argument: $1" >&2
          usage
          exit 2
        fi
        shift
        ;;
    esac
  done

  if [[ "$run" -eq 1 ]]; then
    run_gc_stress
  fi

  if [[ -z "$log_path" ]]; then
    log_path="build/logs/oren_stage2_native_quick_integration.log"
  fi
  if [[ ! -f "$log_path" ]]; then
    echo "error: log not found: $log_path" >&2
    exit 2
  fi

  local max=0
  local hits
  hits=$(awk '
    {
      if (match($0, /dedup_hits=([0-9]+)/, m)) {
        v = m[1] + 0
        if (v > max) { max = v }
      }
    }
    END {
      print max
    }
  ' "$log_path")

  if [[ "${hits:-0}" -le 0 ]]; then
    echo "no dedup_hits found in: $log_path"
    exit 1
  fi

  local mult="${DEDUP_CAP_MULT:-4}"
  if ! [[ "$mult" =~ ^[0-9]+$ ]]; then
    echo "error: DEDUP_CAP_MULT must be a positive integer (got: $mult)" >&2
    exit 2
  fi

  local cap=$((hits * mult))
  if [[ "$cap" -lt 1 ]]; then
    cap=1
  fi

  echo "alloc_index dedup_hits max: $hits"
  echo "suggested cap (hits * $mult): $cap"
  echo "export OREN_TRACE_ALLOC_INDEX_DEDUP_CAP=$cap"
}

main "$@"
