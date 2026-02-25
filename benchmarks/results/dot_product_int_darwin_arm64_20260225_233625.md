# dot_product_int benchmark (20260225_233625)

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
| c | 0.006003 | 0.005986 | 0.005598 | 0.006313 |
| oren_c | 0.015416 | 0.015485 | 0.014759 | 0.016580 |
| oren_native | 0.023476 | 0.023334 | 0.022917 | 0.023683 |
| oren_obc | 0.378694 | 0.377774 | 0.372762 | 0.383056 |

Output checksum (stdout): `507588000000`
