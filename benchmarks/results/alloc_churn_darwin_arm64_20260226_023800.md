# alloc_churn benchmark (20260226_023800)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: b9035ad3f494037525571658e74b4eb73361e5bd
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAM=all
- OREN_BENCH_UPDATE_LATEST=1
- OREN_BENCH_UPDATE_LATEST_PRUNE=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002931 | 0.002962 | 0.002865 | 0.003079 |
| oren_c | 0.012568 | 0.012557 | 0.012386 | 0.012697 |
| oren_native | 0.018404 | 0.018439 | 0.018282 | 0.018602 |
| oren_obc | 0.167005 | 0.166888 | 0.164980 | 0.169295 |

Output checksum (stdout): `199990000`
