# dot_product_int benchmark (20260225_182217)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1e81dc28a1d4d88d1e1ddc63949a1f6780bedd28
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005793 | 0.005777 | 0.005458 | 0.006130 |
| oren_c | 0.017210 | 0.017911 | 0.016378 | 0.020281 |
| oren_native | 0.023404 | 0.023728 | 0.023240 | 0.024546 |
| oren_obc | 0.388338 | 0.388497 | 0.386295 | 0.391310 |

Output checksum (stdout): `507588000000`
