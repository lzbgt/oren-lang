#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

case_set="${OREN_ARM64_FAST_DOT_PAIR_POST_MADD_DECISION_LIST_INT_CASES:-baseline unroll2_enabled unroll2_pair_post_enabled unroll2_madd_all_enabled unroll2_pair_post_madd_all_enabled}"
candidate="${OREN_ARM64_FAST_DOT_PAIR_POST_MADD_DECISION_LIST_INT_CANDIDATE:-unroll2_pair_post_madd_all_enabled}"

env \
    OREN_ARM64_FAST_DOT_CASE_DECISION_LIST_INT_TAG="perf-probe-arm64-fast-dot-pair-post-madd-decision-list-int" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_LIST_INT_TITLE="arm64 fast dot pair-post + madd decision list<int> summary" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_LIST_INT_COMPLETE_LABEL="arm64 fast-dot pair-post madd decision list<int> probe" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_LIST_INT_CASES="$case_set" \
    OREN_ARM64_FAST_DOT_CASE_DECISION_LIST_INT_CANDIDATE="$candidate" \
    ./scripts/run_perf_probe_arm64_fast_dot_unroll2_scalar_core_decision_list_int.sh
