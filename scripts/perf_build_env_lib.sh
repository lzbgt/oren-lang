#!/usr/bin/env bash

# Shared parser for comma-separated Oren build env overrides used by perf scripts.

perf_build_env_to_nul() {
    local raw="${1:-}"
    local parts=()
    local old_ifs="$IFS"
    if [[ -z "$raw" ]]; then
        return 0
    fi
    IFS=','
    read -r -a parts <<<"$raw"
    IFS="$old_ifs"
    printf '%s\0' "${parts[@]}"
}

perf_build_env_read_array() {
    local raw="${1:-}"
    local part
    PERF_BUILD_ENV_PARTS=()
    while IFS= read -r -d '' part; do
        PERF_BUILD_ENV_PARTS+=("$part")
    done < <(perf_build_env_to_nul "$raw")
}
