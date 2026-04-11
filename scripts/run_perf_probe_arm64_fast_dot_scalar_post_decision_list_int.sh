#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

case_set="${OREN_ARM64_FAST_DOT_SCALAR_POST_DECISION_LIST_INT_CASES:-baseline scalar_post_enabled scalar_enabled scalar_post_madd_enabled}"
candidate="${OREN_ARM64_FAST_DOT_SCALAR_POST_DECISION_LIST_INT_CANDIDATE:-scalar_post_madd_enabled}"

env \
    OREN_ARM64_FAST_DOT_CASE_DECISION_LIST_INT_TAG="perf-probe-arm64-fast-dot-scalar-post-decision-list-int" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_LIST_INT_TITLE="arm64 fast dot scalar-post decision list<int> summary" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_LIST_INT_COMPLETE_LABEL="arm64 fast-dot scalar-post decision list<int> probe" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_LIST_INT_CASES="$case_set" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_LIST_INT_CANDIDATE="$candidate" \
    ./scripts/run_perf_probe_arm64_fast_dot_unroll2_scalar_core_decision_list_int.sh
