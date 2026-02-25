# alloc_churn benchmark (20260226_020521)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 8ac5312976f7826dcda43cb91a46757ed30a672e
- runs: 3 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_ENV_BUILD_OREN=OREN_OPT_LOOP_LIST_REUSE=1
- OREN_BENCH_PROGRAMS=alloc_churn
- OREN_BENCH_RUNS=3
- OREN_BENCH_SKIP_OBC=1
- OREN_BENCH_WARMUPS=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002791 | 0.002862 | 0.002780 | 0.003014 |
| oren_c | 0.012598 | 0.012559 | 0.012476 | 0.012604 |
| oren_native | 0.017791 | 0.017788 | 0.017774 | 0.017799 |

Output checksum (stdout): `199990000`
