#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/readiness_report.sh [options]

Options:
  --profile <minimal|quick|full>  Selects the verification profile (default: quick).
  --minimal                       Alias for --profile minimal.
  --full                          Alias for --profile full.
  --out <path>                    Write the report markdown to <path>.
  --keep-going                    Run all steps even if one fails.
  --dry-run                       Print the plan without running commands.
  -h, --help                      Show this help.

Profiles:
  minimal: make verify-native-quick
  quick:   make verify-native-quick-simd + make verify-backend-parity
  full:    quick + make verify-native-quick-gc + make verify-runtime-robustness
EOF
}

profile="quick"
out_path=""
keep_going=0
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      profile="${2:-}"
      shift 2
      ;;
    --minimal)
      profile="minimal"
      shift
      ;;
    --full)
      profile="full"
      shift
      ;;
    --out)
      out_path="${2:-}"
      shift 2
      ;;
    --keep-going)
      keep_going=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$profile" != "minimal" && "$profile" != "quick" && "$profile" != "full" ]]; then
  echo "ERROR: invalid profile: $profile" >&2
  usage >&2
  exit 2
fi

timestamp="$(date +%Y%m%d_%H%M%S)"
report_dir="build/reports"
log_dir="build/logs/readiness_${timestamp}"

mkdir -p "$report_dir" "$log_dir"

if [[ -z "$out_path" ]]; then
  out_path="${report_dir}/readiness_report_${timestamp}.md"
else
  mkdir -p "$(dirname "$out_path")"
fi

git_rev="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
git_status="$(git status --porcelain 2>/dev/null || true)"
git_dirty="clean"
if [[ -n "$git_status" ]]; then
  git_dirty="dirty"
fi

uname_s="$(uname -s)"
uname_m="$(uname -m)"

declare -a step_names
declare -a step_cmds
declare -a step_logs
declare -a step_results
declare -a step_durations

add_step() {
  step_names+=("$1")
  step_cmds+=("$2")
}

case "$profile" in
  minimal)
    add_step "verify-native-quick" "make verify-native-quick"
    ;;
  quick)
    add_step "verify-native-quick-simd" "make verify-native-quick-simd"
    add_step "verify-backend-parity" "make verify-backend-parity"
    ;;
  full)
    add_step "verify-native-quick-simd" "make verify-native-quick-simd"
    add_step "verify-backend-parity" "make verify-backend-parity"
    add_step "verify-native-quick-gc" "make verify-native-quick-gc"
    add_step "verify-runtime-robustness" "make verify-runtime-robustness"
    ;;
esac

run_step() {
  local name="$1"
  local cmd="$2"
  local log="${log_dir}/${name}.log"
  local start_ts
  local end_ts
  local duration
  local rc=0

  start_ts="$(date +%s)"
  if [[ "$dry_run" == "1" ]]; then
    rc=0
  else
    set +e
    eval "$cmd" >"$log" 2>&1
    rc=$?
    set -e
  fi
  end_ts="$(date +%s)"
  duration="$((end_ts - start_ts))"

  step_logs+=("$log")
  step_durations+=("$duration")
  if [[ "$rc" -eq 0 ]]; then
    step_results+=("OK")
  else
    step_results+=("FAIL ($rc)")
  fi
  return "$rc"
}

had_failure=0
first_failure_rc=0
aborted=0

for i in "${!step_names[@]}"; do
  name="${step_names[$i]}"
  cmd="${step_cmds[$i]}"

  echo "== readiness: ${name} =="
  echo "cmd: ${cmd}"
  if [[ "$dry_run" == "1" ]]; then
    echo "dry-run: skipping execution"
  else
    echo "log: ${log_dir}/${name}.log"
  fi

  run_step "$name" "$cmd"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "result: OK"
  else
    echo "result: FAIL"
    had_failure=1
    if [[ "$first_failure_rc" -eq 0 ]]; then
      first_failure_rc="$rc"
    fi
    if [[ "$keep_going" != "1" ]]; then
      aborted=1
      break
    fi
  fi
done

overall="PASS"
if [[ "$had_failure" == "1" ]]; then
  overall="FAIL"
fi

{
  echo "# Oren readiness report"
  echo ""
  echo "- timestamp: ${timestamp}"
  echo "- profile: ${profile}"
  echo "- host: ${uname_s} ${uname_m}"
  echo "- git: ${git_rev} (${git_dirty})"
  echo "- logs: ${log_dir}"
  echo "- dry-run: ${dry_run}"
  echo ""
  echo "## Summary"
  echo ""
  echo "- overall: ${overall}"
  if [[ "$aborted" == "1" ]]; then
    echo "- note: aborted early on first failure (use --keep-going to run all steps)"
  fi
  echo ""
  echo "## Steps"
  echo ""
  for i in "${!step_names[@]}"; do
    name="${step_names[$i]}"
    cmd="${step_cmds[$i]}"
    log="${step_logs[$i]:-}"
    result="${step_results[$i]:-SKIPPED}"
    duration="${step_durations[$i]:-0}"
    if [[ "$dry_run" == "1" ]]; then
      echo "- ${name}: ${result} (${duration}s)"
      echo "  - cmd: \`${cmd}\`"
    else
      echo "- ${name}: ${result} (${duration}s)"
      echo "  - cmd: \`${cmd}\`"
      echo "  - log: \`${log}\`"
    fi
  done
} >"$out_path"

echo "== readiness report =="
echo "report: ${out_path}"
echo "overall: ${overall}"

if [[ "$had_failure" == "1" ]]; then
  exit "${first_failure_rc:-1}"
fi
