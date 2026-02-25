# dot_product_int benchmark (20260226_025027)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: fb19789ed2ceb7ef2ccff76a96a66de60d6bc967
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=dot_product,dot_product_int
- OREN_BENCH_UPDATE_LATEST=1
- OREN_BENCH_UPDATE_LATEST_PRUNE=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005296 | 0.005334 | 0.005244 | 0.005459 |
| oren_c | 0.015252 | 0.015576 | 0.014632 | 0.016924 |
| oren_native | 0.021807 | 0.021827 | 0.021603 | 0.022140 |
| oren_obc | 0.379132 | 0.377784 | 0.374489 | 0.379643 |

Output checksum (stdout): `507588000000`
