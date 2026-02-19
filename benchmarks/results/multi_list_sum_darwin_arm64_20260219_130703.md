# multi_list_sum benchmark (20260219_130703)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 7fefeb20df4e4072ad952a3e01dc99d71c06a8af
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008349 | 0.008458 | 0.008124 | 0.008856 |
| oren_c | 0.017322 | 0.017436 | 0.016956 | 0.017989 |
| oren_native | 0.030751 | 0.030660 | 0.030317 | 0.030922 |
| oren_obc | 0.015799 | 0.015814 | 0.015377 | 0.016359 |

Output checksum (stdout): `2995000000`
