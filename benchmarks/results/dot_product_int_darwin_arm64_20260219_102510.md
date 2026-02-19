# dot_product_int benchmark (20260219_102510)

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
| c | 0.004725 | 0.004730 | 0.004682 | 0.004816 |
| oren_c | 0.016077 | 0.016216 | 0.016020 | 0.016486 |
| oren_native | 0.024478 | 0.024513 | 0.024324 | 0.024700 |
| oren_obc | 0.552158 | 0.552752 | 0.551581 | 0.555682 |

Output checksum (stdout): `507588000000`
