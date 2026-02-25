# alloc_churn benchmark (20260225_233615)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 3be1b4679a1c76b14e25fcfcb3a75bd8c32b9c41
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAM=all
- OREN_BENCH_UPDATE_LATEST=1
- OREN_BENCH_UPDATE_LATEST_PRUNE=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002971 | 0.003105 | 0.002889 | 0.003768 |
| oren_c | 0.014580 | 0.014585 | 0.014088 | 0.014905 |
| oren_native | 0.138609 | 0.137566 | 0.132784 | 0.139773 |
| oren_obc | 0.165586 | 0.165693 | 0.164479 | 0.167621 |

Output checksum (stdout): `199990000`
