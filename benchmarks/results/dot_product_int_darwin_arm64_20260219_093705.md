# dot_product_int benchmark (20260219_093705)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 9374a14858ae150cd7a7f5d1893c9c024df3e5d0
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004883 | 0.004867 | 0.004800 | 0.004916 |
| oren_c | 0.017364 | 0.017436 | 0.017342 | 0.017735 |
| oren_native | 0.024655 | 0.024677 | 0.024530 | 0.024919 |
| oren_obc | 0.546758 | 0.546928 | 0.544550 | 0.549529 |

Output checksum (stdout): `507588000000`
