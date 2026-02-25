# dot_product benchmark (20260225_233622)

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
| c | 0.005544 | 0.005594 | 0.005423 | 0.005824 |
| oren_c | 0.015172 | 0.015333 | 0.014828 | 0.016124 |
| oren_native | 0.023952 | 0.024048 | 0.023737 | 0.024669 |
| oren_obc | 0.387434 | 0.387175 | 0.385469 | 0.387862 |

Output checksum (stdout): `507588000000`
