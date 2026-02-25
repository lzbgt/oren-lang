# dot_product benchmark (20260226_022915)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 58e3b66a8f2048825df0c99b821c4c3353016737
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=loop_sum,dot_product,dot_product_int
- OREN_BENCH_UPDATE_LATEST=1
- OREN_BENCH_UPDATE_LATEST_PRUNE=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005792 | 0.005862 | 0.005739 | 0.006169 |
| oren_c | 0.014675 | 0.014904 | 0.014022 | 0.016619 |
| oren_native | 0.023031 | 0.023147 | 0.022795 | 0.024003 |
| oren_obc | 0.385035 | 0.385202 | 0.380917 | 0.388483 |

Output checksum (stdout): `507588000000`
