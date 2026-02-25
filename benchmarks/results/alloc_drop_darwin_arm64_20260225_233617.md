# alloc_drop benchmark (20260225_233617)

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
| c | 0.003191 | 0.003188 | 0.003104 | 0.003312 |
| oren_c | 0.002811 | 0.002887 | 0.002690 | 0.003154 |
| oren_native | 0.004579 | 0.004552 | 0.004377 | 0.004619 |
| oren_obc | 0.004276 | 0.004407 | 0.004251 | 0.004743 |

Output checksum (stdout): `alloc_drop keep=11`
