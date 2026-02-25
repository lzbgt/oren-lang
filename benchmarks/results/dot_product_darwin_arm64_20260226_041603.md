# dot_product benchmark (20260226_041603)

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
| c | 0.005437 | 0.005384 | 0.005197 | 0.005606 |
| oren_c | 0.013177 | 0.013252 | 0.012906 | 0.013804 |
| oren_native | 0.013223 | 0.013252 | 0.013198 | 0.013381 |
| oren_obc | 0.414654 | 0.414433 | 0.411773 | 0.416469 |

Output checksum (stdout): `507588000000`
