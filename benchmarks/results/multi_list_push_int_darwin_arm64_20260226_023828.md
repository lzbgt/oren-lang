# multi_list_push_int benchmark (20260226_023828)

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
| c | 0.008423 | 0.008389 | 0.008237 | 0.008528 |
| oren_c | 0.037022 | 0.036977 | 0.036724 | 0.037272 |
| oren_native | 0.028302 | 0.028236 | 0.027857 | 0.028424 |
| oren_obc | 0.533589 | 0.533506 | 0.531029 | 0.536005 |

Output checksum (stdout): `2995000000`
