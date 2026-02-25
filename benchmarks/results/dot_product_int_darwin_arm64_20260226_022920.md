# dot_product_int benchmark (20260226_022920)

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
| c | 0.005613 | 0.005630 | 0.005432 | 0.005832 |
| oren_c | 0.014179 | 0.014187 | 0.013907 | 0.014496 |
| oren_native | 0.021692 | 0.021681 | 0.021636 | 0.021721 |
| oren_obc | 0.375954 | 0.375889 | 0.374143 | 0.378718 |

Output checksum (stdout): `507588000000`
