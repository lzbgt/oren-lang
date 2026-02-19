# Benchmarks (Local perf comparisons)

This folder contains **local, reproducible** microbenchmarks intended to compare:

- pure C baseline
- Oren (C backend)
- Oren (native backend)
- Oren bytecode running on AVM (`.obc`)

Benchmarks:

- `loop_sum` (tight integer loop with simple arithmetic)
- `array_sum` (list/array fill + sum; stresses element access and loop overhead)
- `array_sum_int` (list<int> fill + sum; evaluates unboxed list<int> path)
- `dot_product` (two-array dot product; stresses loads, multiply, and loop)
- `dot_product_int` (list<int> dot product; evaluates unboxed list<int> path)
- `multi_list_push_int` (three list<int> pushes per loop + sum; stresses unboxed list<int> push throughput)
- `multi_list_sum` (three boxed list reads per loop + sum; stresses boxed list access + add lowering)
- `alloc_churn` (allocation churn with periodic GC to surface leaks)
- `alloc_drop` (allocation churn with periodic drops to surface GC/root leaks; respects `OREN_BENCH_ITERS`)

## Latest snapshot

See `benchmarks/RESULTS_LATEST.md` for the latest M2 baseline summary (medians + C-relative ratios).

## Run

```bash
python3 benchmarks/run_benchmarks.py
```

Optional knobs:

- `OREN_BENCH_RUNS=<n>` (default: 5)
- `OREN_BENCH_WARMUPS=<n>` (default: 1)
- `OREN_BENCH_RSS=1` (capture per-run max RSS via `/usr/bin/time`)
- `OREN_BENCH_PROGRAM=<name>` (default: `loop_sum`)
- `OREN_BENCH_CC=<compiler>` (override C compiler; auto-detects `cc/clang/gcc` otherwise)
- `OREN_BENCH_ENV_ALL=K=V,...` (apply env overrides to all variants)
- `OREN_BENCH_ENV_C=K=V,...`
- `OREN_BENCH_ENV_OREN_C=K=V,...`
- `OREN_BENCH_ENV_OREN_NATIVE=K=V,...`
- `OREN_BENCH_ENV_OREN_OBC=K=V,...`
- `OREN_BENCH_ITERS=<n>` (used by `alloc_drop`; default: 10000)
- `OREN_BENCH_SKIP_OBC=1` (skip AVM/OBC build+run; useful on Windows if `avm.exe` is unavailable)
- `OREN_BENCH_SKIP_C=1` (skip the pure C baseline build+run)
- `OREN_BENCH_SKIP_OREN_C=1` (skip the Oren C-backend build+run; useful if no C compiler is installed)
- `OREN_BENCH_SKIP_NATIVE=1` (skip native backend build+run)
- Example: `OREN_BENCH_ENV_OREN_NATIVE=OREN_LIST_ASSUME_LIST=1` to probe list-validation overhead (unsafe; perf-only).
- Example: `OREN_BENCH_ENV_OREN_C=OREN_LIST_SKIP_LOCKS=1` to skip list/map locks in the C backend (unsafe; perf-only).
- Example: `OREN_BENCH_ENV_OREN_C=OREN_LIST_FORCE_LOCKS=1` to force list/map locks in the C backend (useful for safety baselines).
- Example: `OREN_BENCH_ENV_OREN_C=OREN_TRACE_LIST_LOCKS=1` to print lock gating state once at first list access.
- Compiler env example (affects codegen): `OREN_NATIVE_ASSUME_LIST_INDEX=1 python3 benchmarks/run_benchmarks.py` (unsafe; perf-only).

Results are written to:

- `benchmarks/results/<program>_<platform>_<timestamp>.md`
- `benchmarks/results/<program>_<platform>_<timestamp>.json`

Build logs are stored under `build/logs/` with a `bench_build_*` prefix.

## Notes

- The Oren sources are compiled with `./oren_stage2` for consistency.
- Native builds use `--no-debug` to approximate release behavior.
- The OBC benchmark uses `./avm` and runs without explicit capability restrictions.
  On Windows, the runner looks for `.exe` tool suffixes automatically.

If you need a different loop size, change `n` in `benchmarks/loop_sum/loop_sum.oren`
(and the matching C baseline) so all variants remain comparable.
