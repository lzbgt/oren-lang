# dot_product_int benchmark (20260226_023818)

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
| c | 0.005082 | 0.005107 | 0.004986 | 0.005274 |
| oren_c | 0.012251 | 0.012367 | 0.012045 | 0.012938 |
| oren_native | 0.022271 | 0.022249 | 0.021971 | 0.022449 |
| oren_obc | 0.386286 | 0.384764 | 0.381111 | 0.386989 |

Output checksum (stdout): `507588000000`
