# array_sum_int benchmark (20260219_103557)

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
| c | 0.004327 | 0.004499 | 0.003972 | 0.005112 |
| oren_c | 0.011515 | 0.011518 | 0.011301 | 0.011660 |
| oren_native | 0.020331 | 0.020562 | 0.020229 | 0.021368 |
| oren_obc | 0.263552 | 0.263916 | 0.263244 | 0.265579 |

Output checksum (stdout): `999000000`
