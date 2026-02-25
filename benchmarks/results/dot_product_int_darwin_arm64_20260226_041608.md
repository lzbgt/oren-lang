# dot_product_int benchmark (20260226_041608)

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
| c | 0.005420 | 0.005517 | 0.005418 | 0.005715 |
| oren_c | 0.012842 | 0.012897 | 0.012804 | 0.013006 |
| oren_native | 0.013794 | 0.013755 | 0.013402 | 0.014079 |
| oren_obc | 0.421071 | 0.425700 | 0.410957 | 0.442858 |

Output checksum (stdout): `507588000000`
