# array_sum_int benchmark (20260226_025143)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 660bfd043983caf1bbd3b01dcb6bb4d6b0cecde1
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=array_sum_int,multi_list_sum
- OREN_BENCH_UPDATE_LATEST=1
- OREN_BENCH_UPDATE_LATEST_PRUNE=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004350 | 0.004311 | 0.004134 | 0.004419 |
| oren_c | 0.009034 | 0.009505 | 0.008751 | 0.011303 |
| oren_native | 0.016525 | 0.016522 | 0.016254 | 0.016810 |
| oren_obc | 0.253592 | 0.254703 | 0.252875 | 0.257041 |

Output checksum (stdout): `999000000`
