# alloc_drop benchmark (20260320_002728)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 06f441de7ad765f5ee4ace5f1a1d7f5880250ef6
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=loop_sum,dot_product,alloc_churn,alloc_drop
- OREN_BENCH_RUNS=5
- OREN_BENCH_SKIP_OBC=1
- OREN_BENCH_SKIP_OREN_C=1
- OREN_BENCH_UPDATE_LATEST=0
- OREN_BENCH_UPDATE_LATEST_PRUNE=0
- OREN_BENCH_WARMUPS=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002893 | 0.003049 | 0.002883 | 0.003560 |
| oren_native | 0.005263 | 0.005337 | 0.005167 | 0.005693 |

Output checksum (stdout): `alloc_drop keep=11`
