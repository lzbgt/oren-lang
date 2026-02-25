# array_sum_int benchmark (20260225_233620)

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
| c | 0.004614 | 0.004556 | 0.004384 | 0.004640 |
| oren_c | 0.009722 | 0.009888 | 0.009608 | 0.010660 |
| oren_native | 0.018277 | 0.018234 | 0.017961 | 0.018420 |
| oren_obc | 0.257964 | 0.257464 | 0.255127 | 0.259444 |

Output checksum (stdout): `999000000`
