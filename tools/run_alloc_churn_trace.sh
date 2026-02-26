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

./oren_stage2 build benchmarks/alloc_churn/alloc_churn.oren --backend native --no-debug -o "${bin}" > "${build_log}" 2>&1
"${bin}" > "${run_log}" 2>&1
echo "${tag}"
