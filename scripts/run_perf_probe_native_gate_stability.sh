#!/usr/bin/env bash
set -euo pipefail

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-native-gate-stability-${ts}.log"
sweeps="${OREN_NATIVE_GATE_STABILITY_SWEEPS:-3}"
programs="${OREN_BENCH_PROGRAMS:-array_sum,dot_product}"
runs="${OREN_BENCH_RUNS:-5}"
warmups="${OREN_BENCH_WARMUPS:-1}"
cov_warn="${OREN_BENCH_COV_WARN:-0.10}"

probe_dir="$log_dir/perf-probe-native-gate-stability-${ts}"
mkdir -p "$probe_dir"

run_logs_file="$probe_dir/run_logs.txt"
summary_logs_file="$probe_dir/summary_logs.txt"
: >"$run_logs_file"
: >"$summary_logs_file"

i=1
while [[ "$i" -le "$sweeps" ]]; do
    run_log="$probe_dir/sweep-${i}.run.log"
    env \
        OREN_BENCH_PROGRAMS="$programs" \
        OREN_BENCH_RUNS="$runs" \
        OREN_BENCH_WARMUPS="$warmups" \
        OREN_BENCH_COV_WARN="$cov_warn" \
        make perf-gate-native >"$run_log" 2>&1
    printf '%s\n' "$run_log" >>"$run_logs_file"
    sed -n 's/^summary: //p' "$run_log" | tail -n 1 >>"$summary_logs_file"
    i=$((i + 1))
done

RUN_LOGS_FILE="$run_logs_file" SUMMARY_LOGS_FILE="$summary_logs_file" python3 - <<'PY' >"$summary_log"
import os
import statistics

run_logs = [
    line.strip()
    for line in open(os.environ["RUN_LOGS_FILE"], "r", encoding="utf-8")
    if line.strip()
]
summary_logs = [
    line.strip()
    for line in open(os.environ["SUMMARY_LOGS_FILE"], "r", encoding="utf-8")
    if line.strip()
]

programs = {}
for idx, path in enumerate(summary_logs, start=1):
    current = None
    if not path:
        continue
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line:
                continue
            if not line.startswith(" ") and not line.startswith("native gate summary:"):
                current = line
                programs.setdefault(current, {"ratios": [], "warn_sweeps": []})
                continue
            if current is None:
                continue
            if "native/C median ratio=" in line:
                ratio = float(line.split("native/C median ratio=")[1].split("x", 1)[0])
                programs[current]["ratios"].append((idx, ratio))
            if "warning: high gate variance" in line:
                programs[current]["warn_sweeps"].append(idx)

print("native gate stability probe summary")
print("")
print(f"sweeps: {len(summary_logs)}")
for idx, (run_log, summary_log) in enumerate(zip(run_logs, summary_logs), start=1):
    print(f"sweep {idx}: run={run_log}")
    print(f"sweep {idx}: summary={summary_log}")
print("")

for program, data in programs.items():
    ratios = [ratio for _, ratio in data["ratios"]]
    warn_sweeps = data["warn_sweeps"]
    print(program)
    if ratios:
        print(f"  ratio median≈{statistics.median(ratios):.4f}x min={min(ratios):.4f}x max={max(ratios):.4f}x")
    print(f"  warning sweeps={len(warn_sweeps)}/{len(summary_logs)}")
    if warn_sweeps:
        print(f"  warning sweep ids={','.join(str(i) for i in warn_sweeps)}")
    print("")
PY

echo "native gate stability probe complete; summary: $summary_log"
