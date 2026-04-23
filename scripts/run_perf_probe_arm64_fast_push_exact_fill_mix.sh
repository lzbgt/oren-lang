#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ts="$(date +%Y%m%d_%H%M%S)_$$"
log_dir="build/logs"
mkdir -p "$log_dir"

summary_log="$log_dir/perf-probe-arm64-fast-push-exact-fill-mix-${ts}.log"

programs="${OREN_ARM64_FAST_PUSH_EXACT_FILL_MIX_PROGRAMS:-array_sum_int,array_sum_int_step7,dot_product_int}"
n_override="${OREN_ARM64_FAST_PUSH_EXACT_FILL_MIX_N:-${OREN_LIST_INT_C_CEILING_N:-}}"
reps_override="${OREN_ARM64_FAST_PUSH_EXACT_FILL_MIX_REPS:-${OREN_LIST_INT_C_CEILING_REPS:-}}"
tick_mask="${OREN_ARM64_FAST_PUSH_EXACT_FILL_MIX_TICK_MASK:-${OREN_ARM64_FAST_LIST_INT_PUSH_TICK_MASK:-4095}}"

PROGRAMS="$programs" \
N_OVERRIDE="$n_override" \
REPS_OVERRIDE="$reps_override" \
TICK_MASK="$tick_mask" \
python3 - <<'PY' >"$summary_log"
import os
import re
from pathlib import Path


PROGRAMS = [p.strip() for p in os.environ["PROGRAMS"].split(",") if p.strip()]
N_OVERRIDE = os.environ["N_OVERRIDE"].strip()
REPS_OVERRIDE = os.environ["REPS_OVERRIDE"].strip()
TICK_MASK = int(os.environ["TICK_MASK"])

DEFAULT_RE = re.compile(r"^\s*var\s+(n|reps)\s*=\s*(\d+)\s*$")
PUSH_RE = re.compile(
    r"""
    (?P<prefix>.*?)
    list\.int_push\(
        \s*(?P<list>[A-Za-z_][A-Za-z0-9_]*)\s*,
        \s*\(\s*
        (?P<idx>[A-Za-z_][A-Za-z0-9_]*)\s*\*\s*(?P<mul>\d+)\s*\+\s*(?P<add>\d+)
        \s*\)\s*%\s*(?P<mod>\d+)
        \s*
    \)
    """,
    re.X,
)


def tick_period_from_mask(tick_mask: int) -> int:
    if tick_mask < 0:
        return 0
    period = tick_mask + 1
    if period <= 0:
        return 0
    pow2 = 1
    while pow2 < period:
        pow2 *= 2
    if pow2 != period:
        return 0
    return period


def parse_source(path: Path):
    lines = path.read_text(encoding="utf-8").splitlines()
    defaults = {}
    pushes = []
    for lineno, raw in enumerate(lines, start=1):
        m = DEFAULT_RE.match(raw)
        if m and m.group(1) not in defaults:
            defaults[m.group(1)] = int(m.group(2))
        pm = PUSH_RE.search(raw)
        if pm:
            pushes.append(
                {
                    "line": lineno,
                    "list": pm.group("list"),
                    "idx": pm.group("idx"),
                    "mul": int(pm.group("mul")),
                    "add": int(pm.group("add")),
                    "mod": int(pm.group("mod")),
                    "source": raw.strip(),
                }
            )
    return lines, defaults, pushes


def simulate_stream(n: int, mul: int, add: int, mod: int):
    step = mul % mod if mod > 0 else 0
    wide_trips = n // 4
    tail_elems = n % 4
    nowrap_cutoff = None
    nowrap_trips = 0
    wrap_trips = 0
    current = add % mod if mod > 0 else add
    if mod > 0:
        nowrap_window = step * 3
        if nowrap_window >= 0 and nowrap_window < mod:
            nowrap_cutoff = mod - nowrap_window
        for _ in range(wide_trips):
            if nowrap_cutoff is not None and current < nowrap_cutoff:
                nowrap_trips += 1
            else:
                wrap_trips += 1
            current = (current + step * 4) % mod
    return {
        "step": step,
        "wide_trips": wide_trips,
        "tail_elems": tail_elems,
        "nowrap_cutoff": nowrap_cutoff,
        "nowrap_trips": nowrap_trips,
        "wrap_trips": wrap_trips,
        "nowrap_share": (float(nowrap_trips) / float(wide_trips)) if wide_trips > 0 else 0.0,
        "wrap_share": (float(wrap_trips) / float(wide_trips)) if wide_trips > 0 else 0.0,
        "tail_start_value": current,
    }


period = tick_period_from_mask(TICK_MASK)

print("arm64 fast list<int> push exact-program fill mix probe")
print("")
print(f"programs: {', '.join(PROGRAMS)}")
print(f"tick_mask: {TICK_MASK}")
print(f"tick_period: {period}")
print("compiler_gate: single_list_cursor && pushes_per_iter==1 && nonnegative_linear && tick_period%4==0")
print("")

for program in PROGRAMS:
    src = Path(f"benchmarks/{program}/{program}.oren")
    if not src.exists():
        raise SystemExit(f"missing benchmark source: {src}")
    _, defaults, pushes = parse_source(src)
    default_n = defaults.get("n", 0)
    default_reps = defaults.get("reps", 1)
    effective_n = int(N_OVERRIDE) if N_OVERRIDE else default_n
    effective_reps = int(REPS_OVERRIDE) if REPS_OVERRIDE else default_reps
    fill_pushes_per_iter = len(pushes)
    total_fill_push_calls = effective_n * fill_pushes_per_iter
    per_outer_rep = float(total_fill_push_calls) / float(effective_reps) if effective_reps > 0 else 0.0
    single_list_unroll4_applicable = (
        fill_pushes_per_iter == 1 and period > 0 and period % 4 == 0 and pushes[0]["mod"] > 0
    )

    print(f"program: {program}")
    print(f"  source: {src}")
    print(f"  default_n: {default_n}")
    print(f"  default_reps: {default_reps}")
    print(f"  effective_n: {effective_n}")
    print(f"  effective_reps: {effective_reps}")
    print(f"  fill_pushes_per_iter: {fill_pushes_per_iter}")
    print(f"  total_fill_push_calls: {total_fill_push_calls}")
    print(f"  amortized_fill_push_calls_per_outer_rep: {per_outer_rep:.2f}")
    print(f"  single_list_unroll4_applicable: {'yes' if single_list_unroll4_applicable else 'no'}")
    if not single_list_unroll4_applicable:
        if fill_pushes_per_iter != 1:
            print("  ineligible_reason: pushes_per_iter!=1 blocks single_list_cursor/unroll4 gate")
        elif period <= 0 or period % 4 != 0:
            print("  ineligible_reason: tick period is not divisible by 4")
        elif pushes and pushes[0]['mod'] <= 0:
            print("  ineligible_reason: modulo is non-positive")
    for idx, push in enumerate(pushes, start=1):
        sim = simulate_stream(effective_n, push["mul"], push["add"], push["mod"])
        print(f"  push_{idx}_line: {push['line']}")
        print(f"  push_{idx}_list: {push['list']}")
        print(f"  push_{idx}_idx: {push['idx']}")
        print(f"  push_{idx}_source: {push['source']}")
        print(
            f"  push_{idx}_linear: mul={push['mul']} add={push['add']} mod={push['mod']} step_mod={sim['step']}"
        )
        print(f"  push_{idx}_wide_trips: {sim['wide_trips']}")
        print(f"  push_{idx}_tail_elems: {sim['tail_elems']}")
        if sim["nowrap_cutoff"] is not None:
            print(f"  push_{idx}_nowrap_cutoff: {sim['nowrap_cutoff']}")
            print(f"  push_{idx}_hypothetical_isolated_nowrap_trips: {sim['nowrap_trips']}")
            print(f"  push_{idx}_hypothetical_isolated_wrap_trips: {sim['wrap_trips']}")
            print(f"  push_{idx}_hypothetical_isolated_nowrap_share: {sim['nowrap_share'] * 100.0:.4f}%")
            print(f"  push_{idx}_hypothetical_isolated_wrap_share: {sim['wrap_share'] * 100.0:.4f}%")
            print(
                f"  push_{idx}_hypothetical_isolated_wide_trips_per_outer_rep: {float(sim['wide_trips']) / float(effective_reps):.2f}"
            )
        else:
            print(f"  push_{idx}_nowrap_cutoff: unavailable")
        print(f"  push_{idx}_tail_start_value: {sim['tail_start_value']}")
    if single_list_unroll4_applicable:
        print("  program_note: this exact program directly exercises the shipped single-list unroll4 fill branch")
    else:
        print("  program_note: this exact program does not directly exercise the single-list unroll4 fill branch; treat exact shifts here as non-causal control signal for that family")
    print("")
PY

echo "arm64 fast list<int> push exact-program fill mix probe complete; summary: $summary_log"
