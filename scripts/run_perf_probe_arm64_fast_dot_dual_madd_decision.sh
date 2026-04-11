#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

case_set="${OREN_ARM64_FAST_DOT_DUAL_MADD_DECISION_CASES:-baseline unroll2_enabled unroll2_dual_accum_enabled unroll2_dual_madd_enabled unroll2_pair_post_dual_accum_enabled unroll2_pair_post_dual_madd_enabled}"
candidate="${OREN_ARM64_FAST_DOT_DUAL_MADD_DECISION_CANDIDATE:-unroll2_pair_post_dual_madd_enabled}"

env \
    OREN_ARM64_FAST_DOT_CASE_DECISION_TAG="perf-probe-arm64-fast-dot-dual-madd-decision" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_TITLE="arm64 fast dot dual-accum madd decision summary" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_COMPLETE_LABEL="arm64 fast-dot dual-accum madd decision probe" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_METRIC_PROGRAM="dot_product" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_READ_SPLIT_TARGET="perf-probe-arm64-fast-dot-scalar-core-read-split" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_READ_SPLIT_CASES_ENV="OREN_ARM64_FAST_DOT_SCALAR_CORE_READ_SPLIT_CASES" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_READ_SPLIT_SUMMARY_PREFIX="perf-probe-arm64-fast-dot-scalar-core-read-split-" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_GATE_STABILITY_TARGET="perf-probe-arm64-fast-dot-scalar-core-gate-stability" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_GATE_STABILITY_CASES_ENV="OREN_ARM64_FAST_DOT_SCALAR_CORE_GATE_STABILITY_CASES" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_GATE_STABILITY_SUMMARY_PREFIX="perf-probe-arm64-fast-dot-scalar-core-gate-stability-" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_CASES="$case_set" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_CANDIDATE="$candidate" \
    ./scripts/run_perf_probe_arm64_fast_dot_unroll2_scalar_core_decision_list_int.sh
