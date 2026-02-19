# array_sum_int benchmark (20260219_122045)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 164142d78b77a8a39525a1cc0c9b608439cd7cc8
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004162 | 0.004231 | 0.003826 | 0.004699 |
| oren_c | 0.010820 | 0.010810 | 0.010370 | 0.011320 |
| oren_native | 0.020558 | 0.020521 | 0.020195 | 0.020987 |
| oren_obc | 0.005169 | 0.005126 | 0.004901 | 0.005461 |

Output checksum (stdout): `999000000`
