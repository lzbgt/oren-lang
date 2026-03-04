#!/usr/bin/env bash
set -euo pipefail

# Run alloc_churn traces repeatedly until a corruption signature is found
# or the run fails/times out. Tags and logs are written under build/logs/.

max_runs="${1:-50}"
tag_base="${2:-gc_hunt_$(date +%Y%m%d_%H%M%S)}"
sleep_secs="${HUNT_SLEEP_SECS:-0}"
correlate="${ALLOC_CHURN_HUNT_CORRELATE:-${HUNT_CORRELATE:-1}}"
correlate_limit="${ALLOC_CHURN_HUNT_CORRELATE_LIMIT:-5}"
correlate_max="${ALLOC_CHURN_HUNT_CORRELATE_MAX:-50}"
correlate_tool="tools/trace_list_hdr_correlate.py"
python_bin="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")"

log_dir="build/logs"
mkdir -p "${log_dir}"

fail_pat='gc list_int header corrupt|gc list header corrupt|gc_reuse_bad_list|list_corrupt|Runtime Panic'

echo "alloc_churn_hunt: max_runs=${max_runs} tag_base=${tag_base}"

run_idx=1
while [[ "${run_idx}" -le "${max_runs}" ]]; do
  tag="${tag_base}_${run_idx}"
  echo "== run ${run_idx}/${max_runs}: ${tag} =="

  tools/run_alloc_churn_trace.sh "${tag}"

  run_log="${log_dir}/alloc_churn_trace_${tag}.log"
  env_log="${log_dir}/alloc_churn_env_${tag}.log"

  run_status=""
  run_timed_out=""
  if [[ -f "${env_log}" ]]; then
    run_status="$(rg -m 1 '^run_status=' "${env_log}" | cut -d= -f2 || true)"
    run_timed_out="$(rg -m 1 '^run_timed_out=' "${env_log}" | cut -d= -f2 || true)"
  fi

  if [[ -f "${run_log}" ]]; then
    if rg -m 1 -n "${fail_pat}" "${run_log}" >/dev/null; then
      echo "alloc_churn_hunt: corruption signature found in ${run_log}"
      rg -n "${fail_pat}" "${run_log}" | head -n 5
      if [[ "${correlate}" != "0" && -n "${python_bin}" && -f "${correlate_tool}" ]]; then
        correlate_log="${log_dir}/alloc_churn_trace_${tag}_correlate.log"
        if "${python_bin}" "${correlate_tool}" --log "${run_log}" --limit "${correlate_limit}" --max "${correlate_max}" > "${correlate_log}" 2>&1; then
          echo "alloc_churn_hunt: correlate log written to ${correlate_log}"
        else
          echo "alloc_churn_hunt: correlate failed (see ${correlate_log})"
        fi
      fi
      exit 0
    fi
  fi

  if [[ "${run_status}" != "" && "${run_status}" != "0" ]]; then
    if [[ -f "${run_log}" ]]; then
      if rg -m 1 -n "\\[crash_footer_raw\\]" "${run_log}" >/dev/null; then
        echo "alloc_churn_hunt: crash_footer_raw in ${run_log}"
        rg -m 1 -n "\\[crash_footer_raw\\]" "${run_log}"
        if rg -m 1 -n "\\[crash_footer_raw\\] ring idx=" "${run_log}" >/dev/null; then
          echo "alloc_churn_hunt: crash_footer_raw ring dump (first 3)"
          rg -m 3 -n "\\[crash_footer_raw\\] ring idx=" "${run_log}"
        fi
      fi
      if [[ "${correlate}" != "0" && -n "${python_bin}" && -f "${correlate_tool}" ]]; then
        correlate_log="${log_dir}/alloc_churn_trace_${tag}_correlate.log"
        if "${python_bin}" "${correlate_tool}" --log "${run_log}" --limit "${correlate_limit}" --max "${correlate_max}" > "${correlate_log}" 2>&1; then
          echo "alloc_churn_hunt: correlate log written to ${correlate_log}"
        else
          echo "alloc_churn_hunt: correlate failed (see ${correlate_log})"
        fi
      fi
    fi
    echo "alloc_churn_hunt: run_status=${run_status} (see ${env_log})"
    exit 1
  fi
  if [[ "${run_timed_out}" == "1" ]]; then
    if [[ -f "${run_log}" ]]; then
      if rg -m 1 -n "\\[crash_footer_raw\\]" "${run_log}" >/dev/null; then
        echo "alloc_churn_hunt: crash_footer_raw in ${run_log}"
        rg -m 1 -n "\\[crash_footer_raw\\]" "${run_log}"
        if rg -m 1 -n "\\[crash_footer_raw\\] ring idx=" "${run_log}" >/dev/null; then
          echo "alloc_churn_hunt: crash_footer_raw ring dump (first 3)"
          rg -m 3 -n "\\[crash_footer_raw\\] ring idx=" "${run_log}"
        fi
      fi
      if [[ "${correlate}" != "0" && -n "${python_bin}" && -f "${correlate_tool}" ]]; then
        correlate_log="${log_dir}/alloc_churn_trace_${tag}_correlate.log"
        if "${python_bin}" "${correlate_tool}" --log "${run_log}" --limit "${correlate_limit}" --max "${correlate_max}" > "${correlate_log}" 2>&1; then
          echo "alloc_churn_hunt: correlate log written to ${correlate_log}"
        else
          echo "alloc_churn_hunt: correlate failed (see ${correlate_log})"
        fi
      fi
    fi
    echo "alloc_churn_hunt: timed out (see ${env_log})"
    exit 1
  fi

  run_idx=$((run_idx + 1))
  if [[ "${sleep_secs}" != "0" ]]; then
    sleep "${sleep_secs}"
  fi
done

echo "alloc_churn_hunt: completed ${max_runs} runs with no corruption signature."
