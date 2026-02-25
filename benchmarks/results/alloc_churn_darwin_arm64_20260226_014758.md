# alloc_churn benchmark (20260226_014758)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 999731279c85b6f41604481945b8a106cfea03bd
- runs: 3 (warmups: 0)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=alloc_churn,alloc_drop
- OREN_BENCH_RUNS=3
- OREN_BENCH_SKIP_OBC=1
- OREN_BENCH_TRACE_ALLOC_SITE=1
- OREN_BENCH_WARMUPS=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002936 | 0.003142 | 0.002865 | 0.003626 |
| oren_c | 0.013347 | 0.013590 | 0.013264 | 0.014158 |
| oren_native | 0.140544 | 0.143031 | 0.139504 | 0.149045 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 40000 | 0 | 20000 | 0 | 20000 |

Output checksum (stdout): `199990000
199990000
199990000`
