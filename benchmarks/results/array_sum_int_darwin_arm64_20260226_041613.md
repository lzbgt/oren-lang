# array_sum_int benchmark (20260226_041613)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 7d409d9c69b913c305e168462626eaea8b30f1c7
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=dot_product,dot_product_int,array_sum_int
- OREN_BENCH_UPDATE_LATEST=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004201 | 0.004217 | 0.004103 | 0.004407 |
| oren_c | 0.008025 | 0.008077 | 0.007978 | 0.008200 |
| oren_native | 0.008884 | 0.008880 | 0.008638 | 0.009061 |
| oren_obc | 0.278792 | 0.279015 | 0.277908 | 0.280522 |

Output checksum (stdout): `999000000`
