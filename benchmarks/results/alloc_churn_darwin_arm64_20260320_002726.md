# alloc_churn benchmark (20260320_002726)

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
| c | 0.003124 | 0.003146 | 0.002991 | 0.003300 |
| oren_native | 0.021369 | 0.021492 | 0.019500 | 0.023243 |

Output checksum (stdout): `199990000`
