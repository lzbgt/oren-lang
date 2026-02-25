# multi_list_sum benchmark (20260226_023834)

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
| c | 0.008507 | 0.008534 | 0.008342 | 0.008785 |
| oren_c | 0.037564 | 0.037770 | 0.037335 | 0.038988 |
| oren_native | 0.028251 | 0.028331 | 0.028074 | 0.028790 |
| oren_obc | 0.537326 | 0.536652 | 0.532938 | 0.539337 |

Output checksum (stdout): `2995000000`
