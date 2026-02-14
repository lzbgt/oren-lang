# Benchmarks (Local perf comparisons)

This folder contains **local, reproducible** microbenchmarks intended to compare:

- pure C baseline
- Oren (C backend)
- Oren (native backend)
- Oren bytecode running on AVM (`.obc`)

Benchmarks:

- `loop_sum` (tight integer loop with simple arithmetic)
- `alloc_churn` (allocation churn with periodic GC to surface leaks)

## Run

```bash
python3 benchmarks/run_benchmarks.py
```

Optional knobs:

- `OREN_BENCH_RUNS=<n>` (default: 5)
- `OREN_BENCH_WARMUPS=<n>` (default: 1)
- `OREN_BENCH_RSS=1` (capture per-run max RSS via `/usr/bin/time`)
- `OREN_BENCH_PROGRAM=<name>` (default: `loop_sum`)
- `OREN_BENCH_ENV_ALL=K=V,...` (apply env overrides to all variants)
- `OREN_BENCH_ENV_C=K=V,...`
- `OREN_BENCH_ENV_OREN_C=K=V,...`
- `OREN_BENCH_ENV_OREN_NATIVE=K=V,...`
- `OREN_BENCH_ENV_OREN_OBC=K=V,...`

Results are written to:

- `benchmarks/results/<program>_m2_<timestamp>.md`
- `benchmarks/results/<program>_m2_<timestamp>.json`

Build logs are stored under `build/logs/` with a `bench_build_*` prefix.

## Notes

- The Oren sources are compiled with `./oren_stage2` for consistency.
- Native builds use `--no-debug` to approximate release behavior.
- The OBC benchmark uses `./avm` and runs without explicit capability restrictions.

If you need a different loop size, change `n` in `benchmarks/loop_sum/loop_sum.oren`
(and the matching C baseline) so all variants remain comparable.
