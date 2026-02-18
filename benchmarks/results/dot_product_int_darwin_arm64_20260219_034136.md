# dot_product_int benchmark (20260219_034136)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: bc32871e7dfafda94dc9d64bfc661422c7a3f1a8
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004934 | 0.004970 | 0.004756 | 0.005416 |
| oren_c | 0.071982 | 0.071994 | 0.071908 | 0.072076 |
| oren_native | 0.284129 | 0.284119 | 0.282854 | 0.285089 |
| oren_obc | 0.899077 | 0.899516 | 0.896678 | 0.903428 |

Output checksum (stdout): `507588000000`
