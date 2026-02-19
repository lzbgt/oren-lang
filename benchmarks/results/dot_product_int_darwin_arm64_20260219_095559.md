# dot_product_int benchmark (20260219_095559)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 668a079888e4d234bae4375472d26ba8cf93f9d8
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004754 | 0.004772 | 0.004649 | 0.004887 |
| oren_c | 0.017869 | 0.017820 | 0.017390 | 0.018211 |
| oren_native | 0.024716 | 0.024746 | 0.024493 | 0.024972 |
| oren_obc | 0.548461 | 0.548320 | 0.547322 | 0.549855 |

Output checksum (stdout): `507588000000`
