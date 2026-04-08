#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/perf_build_env_lib.sh"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp"
mkdir -p "$log_dir"
mkdir -p "$tmp_dir"
log_path="$log_dir/perf-smoke-list-int-slot-direct-${ts}.log"
contract_bin="${tmp_dir}/list_int_slot_direct_contracts_native"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
build_env_parts=()
perf_build_env_read_array "$build_env_raw"
build_env_parts=("${PERF_BUILD_ENV_PARTS[@]}")

bin_path() {
    local program="$1"
    printf 'build/benchmarks/%s/%s_oren_native\n' "$program" "$program"
}

{
    echo "[build] slot-surface benchmarks backend=native"
    ./scripts/build_perf_artifacts_list_int_slot_direct.sh
    echo "[build] slot-direct contract fixture backend=native"
    if [[ -n "$build_env_raw" ]]; then
        echo "[build_env] ${build_env_raw}"
        env "${build_env_parts[@]}" ./oren_stage2 build tests/fixtures/list_int_slot_direct_contracts.oren --backend native --no-debug --no-cache -o "$contract_bin"
    else
        ./oren_stage2 build tests/fixtures/list_int_slot_direct_contracts.oren --backend native --no-debug --no-cache -o "$contract_bin"
    fi
} >>"$log_path" 2>&1

run_native_check() {
    local program="$1"
    local expected="$2"
    shift 2
    local bin
    bin="$(bin_path "$program")"

    echo "[run] ${program} args='$*'" >>"$log_path"
    local actual
    actual="$("$bin" "$@" 2>>"$log_path" | tr -d '\r')"
    echo "[out] ${program} actual=${actual} expected=${expected}" >>"$log_path"
    if [[ "$actual" != "$expected" ]]; then
        echo "slot-direct perf smoke failed for ${program}: got ${actual}, expected ${expected}" | tee -a "$log_path" >&2
        exit 1
    fi
}

run_contract_ok() {
    echo "[run] slot-direct contract fixture default" >>"$log_path"
    local actual
    actual="$("$contract_bin" 2>>"$log_path" | tr -d '\r')"
    echo "[out] slot-direct contract default actual=${actual}" >>"$log_path"
    if [[ "$actual" != "ok: list_int_slot_direct_contracts" ]]; then
        echo "slot-direct contract smoke failed: got '${actual}'" | tee -a "$log_path" >&2
        exit 1
    fi
}

run_contract_abort() {
    local mode="$1"
    local expect="$2"
    local run_log="${tmp_dir}/list_int_slot_direct_contracts_${mode}_${ts}.log"

    echo "[run] slot-direct contract fixture mode=${mode}" >>"$log_path"
    set +e
    "$contract_bin" "$mode" >"$run_log" 2>&1
    local rc=$?
    set -e
    cat "$run_log" >>"$log_path"
    echo "[rc] slot-direct contract mode=${mode} rc=${rc}" >>"$log_path"
    if [[ "$rc" -eq 0 ]]; then
        echo "slot-direct contract abort smoke failed for ${mode}: expected non-zero exit" | tee -a "$log_path" >&2
        exit 1
    fi
    if ! grep -Eq "$expect" "$run_log"; then
        echo "slot-direct contract abort smoke failed for ${mode}: missing expected panic" | tee -a "$log_path" >&2
        echo "expected regex: ${expect}" | tee -a "$log_path" >&2
        exit 1
    fi
}

run_native_check array_sum_int_slot_direct 205 10 3
run_native_check array_sum_int_slot_direct 710 20 3
run_native_check dot_product_int_slot_direct 6590 10 3
run_native_check dot_product_int_slot_direct 54380 20 3
run_native_check array_sum_int_slot_public 205 10 3
run_native_check array_sum_int_slot_public 710 20 3
run_native_check dot_product_int_slot_public 6590 10 3
run_native_check dot_product_int_slot_public 54380 20 3
run_contract_ok
run_contract_abort MODE_DOT_LEFT_NIL 'list_int_dot_slots_unchecked: length mismatch'
run_contract_abort MODE_DOT_RIGHT_NIL 'list_int_dot_slots_unchecked: length mismatch'
run_contract_abort MODE_DOT_LEN_MISMATCH 'list_int_dot_slots_unchecked: length mismatch'

echo "slot-surface list<int> perf smoke complete; log: $log_path"
