# array_sum benchmark (20260225_233618)

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
| c | 0.004628 | 0.004691 | 0.004508 | 0.004859 |
| oren_c | 0.009425 | 0.009534 | 0.009366 | 0.009906 |
| oren_native | 0.018602 | 0.018642 | 0.018454 | 0.019044 |
| oren_obc | 0.260376 | 0.260364 | 0.258679 | 0.261617 |

Output checksum (stdout): `999000000`
