#!/usr/bin/env bash
set -euo pipefail

tag="${1:-$(date +%Y%m%d_%H%M%S)}"
log_dir="build/logs"
tmp_dir="build/tmp"
mkdir -p "$log_dir" "$tmp_dir"

bin="${tmp_dir}/alloc_churn_trace_${tag}"
build_log="${log_dir}/alloc_churn_build_${tag}.log"
run_log="${log_dir}/alloc_churn_trace_${tag}.log"
env_log="${log_dir}/alloc_churn_env_${tag}.log"
timeout_bin="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || echo "")"

{
  echo "tag=${tag}"
  echo "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git_head=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "uname_s=$(uname -s)"
  echo "uname_m=$(uname -m)"
  echo "compiler=./oren_stage2"
  echo "src=benchmarks/alloc_churn/alloc_churn.oren"
  echo "bin=${bin}"
  echo "build_log=${build_log}"
  echo "run_log=${run_log}"
  echo "env_vars:"
  env | rg '^(OREN|AVM)_' | sort
} > "${env_log}"

build_env=(env)
while IFS='=' read -r name _; do
  case "$name" in
    OREN_*|AVM_*) build_env+=("-u" "$name") ;;
  esac
done < <(env)
if [[ -n "${OREN_PLATFORM:-}" ]]; then
  build_env+=("OREN_PLATFORM=${OREN_PLATFORM}")
fi

"${build_env[@]}" ./oren_stage2 build benchmarks/alloc_churn/alloc_churn.oren --backend native --no-debug -o "${bin}" > "${build_log}" 2>&1
if [[ -n "${ALLOC_CHURN_RUN_TIMEOUT_SECS:-}" && -n "${timeout_bin}" ]]; then
  "${timeout_bin}" -k 2 "${ALLOC_CHURN_RUN_TIMEOUT_SECS}" "${bin}" > "${run_log}" 2>&1
else
  "${bin}" > "${run_log}" 2>&1
fi
echo "${tag}"
