#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/perf_build_env_lib.sh"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
tmp_dir="build/tmp/perf-probe-list-int-specialization-trace-${ts}"
mkdir -p "$log_dir" "$tmp_dir"

summary_log="$log_dir/perf-probe-list-int-specialization-trace-${ts}.log"
build_env_raw="${OREN_BENCH_ENV_BUILD_OREN:-}"
build_env_parts=()
generic_programs="${OREN_LIST_INT_SPECIALIZATION_GENERIC_PROGRAMS:-array_sum,dot_product}"
specialized_programs="${OREN_LIST_INT_SPECIALIZATION_SPECIALIZED_PROGRAMS:-array_sum_int,dot_product_int}"
perf_build_env_read_array "$build_env_raw"
build_env_parts=("${PERF_BUILD_ENV_PARTS[@]}")

build_program() {
    local program="$1"
    local trace_log="$tmp_dir/${program}.build.log"
    local out_bin="$tmp_dir/${program}.native"
    if [[ ${#build_env_parts[@]} -gt 0 ]]; then
        env OREN_TRACE_LIST_INT=1 OREN_TRACE_LIST_RESERVE=1 "${build_env_parts[@]}" \
            ./oren_stage2 build benchmarks/${program}/${program}.oren --backend native --no-debug --no-cache -o "$out_bin" \
            >"$trace_log" 2>&1
    else
        env OREN_TRACE_LIST_INT=1 OREN_TRACE_LIST_RESERVE=1 \
            ./oren_stage2 build benchmarks/${program}/${program}.oren --backend native --no-debug --no-cache -o "$out_bin" \
            >"$trace_log" 2>&1
    fi
    printf '%s\n' "$trace_log"
}

generic_logs=()
specialized_logs=()

old_ifs="$IFS"
IFS=', ' read -r -a generic_array <<< "$generic_programs"
IFS=', ' read -r -a specialized_array <<< "$specialized_programs"
IFS="$old_ifs"

for program in "${generic_array[@]}"; do
    [[ -z "$program" ]] && continue
    generic_logs+=("$program $(build_program "$program")")
done

for program in "${specialized_array[@]}"; do
    [[ -z "$program" ]] && continue
    specialized_logs+=("$program $(build_program "$program")")
done

TRACE_TMP_DIR="$tmp_dir" \
BUILD_ENV="$build_env_raw" \
GENERIC_LOGS="$(printf '%s\n' "${generic_logs[@]}")" \
SPECIALIZED_LOGS="$(printf '%s\n' "${specialized_logs[@]}")" \
python3 - <<'PY' >"$summary_log"
import os


def parse_lines(blob):
    out = []
    for raw in blob.splitlines():
        line = raw.strip()
        if not line:
            continue
        program, path = line.split(" ", 1)
        out.append((program, path))
    return out


def summarize(path):
    metrics = {
        "candidate": 0,
        "rewrite_init": 0,
        "rewrite_ctor": 0,
        "touch": 0,
        "unsafe": 0,
        "list_reserve": 0,
        "list_int_reserve": 0,
        "list_int_push_unchecked": 0,
        "list_push_unchecked": 0,
        "list_int_new_ctor": 0,
    }
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if "[opt] list_int candidate " in line:
                metrics["candidate"] += 1
            if "[opt] list_int rewrite init " in line:
                metrics["rewrite_init"] += 1
            if "[opt] list_int rewrite ctor " in line:
                metrics["rewrite_ctor"] += 1
                if "ctor=STD_list_int_new" in line or "ctor=oren_new_list_int" in line:
                    metrics["list_int_new_ctor"] += 1
            if "[opt] list_int touch " in line:
                metrics["touch"] += 1
            if "[opt] list_int unsafe " in line:
                metrics["unsafe"] += 1
            if "[opt] list_reserve name=" in line:
                metrics["list_reserve"] += 1
            if "[opt] list_int_reserve name=" in line:
                metrics["list_int_reserve"] += 1
            if "[opt] list_int_push_unchecked name=" in line:
                metrics["list_int_push_unchecked"] += 1
            if "[opt] list_push_unchecked name=" in line:
                metrics["list_push_unchecked"] += 1
    return metrics


def emit_group(title, items):
    print(title)
    print("")
    for program, path in items:
        metrics = summarize(path)
        print(f"{program}:")
        print(f"  trace_log: {path}")
        for key in [
            "candidate",
            "rewrite_init",
            "rewrite_ctor",
            "list_int_new_ctor",
            "touch",
            "unsafe",
            "list_reserve",
            "list_int_reserve",
            "list_int_push_unchecked",
            "list_push_unchecked",
        ]:
            print(f"  {key}: {metrics[key]}")
        print("")


print("list<int> specialization trace probe summary")
print("")
build_env = os.environ.get("BUILD_ENV", "")
if build_env:
    print(f"build_env: {build_env}")
print(f"tmp_dir: {os.environ['TRACE_TMP_DIR']}")
print("")
emit_group("generic", parse_lines(os.environ["GENERIC_LOGS"]))
emit_group("specialized", parse_lines(os.environ["SPECIALIZED_LOGS"]))
PY

echo "list<int> specialization trace probe complete; summary: $summary_log"
