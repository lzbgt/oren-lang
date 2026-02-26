# alloc_churn benchmark (20260226_161846)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: c43993469b865c61ad2b68cf3bfbb421a126c608
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=alloc_churn,alloc_drop

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002815 | 0.002907 | 0.002747 | 0.003156 |
| oren_c | 0.013625 | 0.013449 | 0.012433 | 0.014559 |
| oren_native | 0.018625 | 0.018552 | 0.018228 | 0.018830 |
| oren_obc | 0.173614 | 0.173778 | 0.171110 | 0.176554 |

Output checksum (stdout): `199990000`
