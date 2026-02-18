# array_sum benchmark (20260219_071812)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 8ffd0faeebe1631804de6db1d1d154b43762d3ea
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003819 | 0.003888 | 0.003797 | 0.004043 |
| oren_c | 0.114611 | 0.114621 | 0.114337 | 0.114959 |
| oren_native | 0.141080 | 0.141533 | 0.140969 | 0.142754 |
| oren_obc | 0.622302 | 0.622385 | 0.619454 | 0.626065 |

Output checksum (stdout): `999000000`
