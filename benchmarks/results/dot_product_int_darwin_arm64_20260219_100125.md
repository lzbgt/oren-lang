# dot_product_int benchmark (20260219_100125)

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
| c | 0.004867 | 0.004913 | 0.004777 | 0.005099 |
| oren_c | 0.017617 | 0.017583 | 0.017039 | 0.018000 |
| oren_native | 0.024564 | 0.024560 | 0.024387 | 0.024767 |
| oren_obc | 0.547946 | 0.548369 | 0.546271 | 0.550537 |

Output checksum (stdout): `507588000000`
