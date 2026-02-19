# dot_product_int benchmark (20260219_182540)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 2f7eccd9123d38fda04388891f271292a8414a9e
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005216 | 0.005332 | 0.004975 | 0.005651 |
| oren_c | 0.012870 | 0.012816 | 0.012087 | 0.013508 |
| oren_native | 0.025346 | 0.025137 | 0.024601 | 0.025521 |
| oren_obc | 0.009547 | 0.009611 | 0.009451 | 0.009951 |

Output checksum (stdout): `507588000000`
