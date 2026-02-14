# Benchmarks (Local perf comparisons)

This folder contains **local, reproducible** microbenchmarks intended to compare:

- pure C baseline
- Oren (C backend)
- Oren (native backend)
- Oren bytecode running on AVM (`.obc`)

The initial benchmark is `loop_sum`, a tight integer loop with simple arithmetic.

## Run

```bash
python3 benchmarks/run_benchmarks.py
```

Optional knobs:

- `OREN_BENCH_RUNS=<n>` (default: 5)
- `OREN_BENCH_WARMUPS=<n>` (default: 1)

Results are written to:

- `benchmarks/results/loop_sum_m2_<timestamp>.md`
- `benchmarks/results/loop_sum_m2_<timestamp>.json`

Build logs are stored under `build/logs/` with a `bench_build_*` prefix.

## Notes

- The Oren sources are compiled with `./oren_stage2` for consistency.
- Native builds use `--no-debug` to approximate release behavior.
- The OBC benchmark uses `./avm` and runs without explicit capability restrictions.

If you need a different loop size, change `n` in `benchmarks/loop_sum/loop_sum.oren`
(and the matching C baseline) so all variants remain comparable.
