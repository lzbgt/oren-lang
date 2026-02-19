# dot_product_int benchmark (20260219_103604)

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
| c | 0.005524 | 0.005576 | 0.005194 | 0.005854 |
| oren_c | 0.018334 | 0.018232 | 0.017762 | 0.018564 |
| oren_native | 0.025093 | 0.025043 | 0.024785 | 0.025329 |
| oren_obc | 0.553466 | 0.553036 | 0.551391 | 0.554791 |

Output checksum (stdout): `507588000000`
