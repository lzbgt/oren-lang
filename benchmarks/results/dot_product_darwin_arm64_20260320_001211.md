# dot_product benchmark (20260320_001211)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: c8bb4e927059643df3a55149e225522b957dc1e2
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
| c | 0.005691 | 0.005673 | 0.005403 | 0.006013 |
| oren_native | 0.014312 | 0.014308 | 0.013846 | 0.014773 |

Output checksum (stdout): `507588000000`
