#!/usr/bin/env bash
set -euo pipefail

# Import a stage2 self-host build failure log into the repo for diagnosis.
#
# Motivation:
# - Sometimes the remote Win11/WSL2 host is unreachable (proxy/DNS issues), so
#   `scripts/fetch_remote_file.sh` cannot download logs automatically.
# - We still want the full original log content stored in-repo under `project-doc/`
#   (no copy/paste into chat), and then run the bounded analyzer.
#
# This script:
# 1) Copies the provided local log into `project-doc/remote_logs/<timestamp>/`.
# 2) Optionally runs `scripts/analyze_stage2_failure_log.sh` on the copied log.
#
# Output is intentionally bounded (paths + analyzer output only).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SRC=""
OUT_DIR=""
OUT_NAME=""
TRACE=0
ANALYZE=0
MAX_LINES=60
TAIL_LINES=120

usage() {
  cat <<'EOF'
Usage:
  scripts/import_stage2_failure_log.sh --src <LOCAL_LOG_PATH> [--out-name <name>] [--out-dir <dir>] [--analyze] [--max N] [--tail N] [--trace]

Examples:
  ./scripts/import_stage2_failure_log.sh --src ./s2_build_failure.log --analyze
  ./scripts/import_stage2_failure_log.sh --src /tmp/s2_build_failure.log --out-name s2_build_failure.log --analyze
  ./scripts/import_stage2_failure_log.sh --src project-doc/remote_logs/manual/s2.log --analyze --max 30 --tail 80

Notes:
  - This stores the full original log under `project-doc/remote_logs/<timestamp>/`.
  - Analyzer output is bounded; the full log is not printed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src)
      SRC="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --out-name)
      OUT_NAME="${2:-}"
      shift 2
      ;;
    --analyze)
      ANALYZE=1
      shift
      ;;
    --max)
      MAX_LINES="${2:-}"
      shift 2
      ;;
    --tail)
      TAIL_LINES="${2:-}"
      shift 2
      ;;
    --trace)
      TRACE=1
      shift
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

if [[ -z "$SRC" ]]; then
  echo "ERROR: --src is required" >&2
  usage >&2
  exit 2
fi

if [[ "$TRACE" -ne 0 ]]; then
  set -x
fi

if [[ ! -f "$SRC" ]]; then
  echo "ERROR: log not found: $SRC" >&2
  exit 2
fi

ts="$(date -u '+%Y%m%d_%H%M%S')"
if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="project-doc/remote_logs/${ts}"
fi
mkdir -p "$OUT_DIR"

base="$(basename "$SRC")"
if [[ -n "$OUT_NAME" ]]; then
  base="$OUT_NAME"
fi
dst="${OUT_DIR}/${base}"

cp -f "$SRC" "$dst"

echo "OK: imported log"
echo "src=$SRC"
echo "dst=$dst"

if [[ "$ANALYZE" -ne 0 ]]; then
  echo ""
  ./scripts/analyze_stage2_failure_log.sh "$dst" --max "$MAX_LINES" --tail "$TAIL_LINES"
fi

