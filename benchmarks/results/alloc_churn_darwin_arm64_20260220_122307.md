# alloc_churn benchmark (20260220_122307)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a0033b496e44927210b31551a27e1d1e3c81627c
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002595 | 0.002597 | 0.002435 | 0.002697 |
| oren_c | 0.030085 | 0.030087 | 0.029888 | 0.030309 |
| oren_native | 3.526135 | 3.524216 | 3.517954 | 3.530800 |
| oren_obc | 0.162101 | 0.162692 | 0.161611 | 0.164970 |

Output checksum (stdout): `199990000`
