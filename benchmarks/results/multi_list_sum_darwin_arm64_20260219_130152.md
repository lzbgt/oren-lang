# multi_list_sum benchmark (20260219_130152)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 99815d1bd7fe3c102863268dbb99c5d2987619e3
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008617 | 0.008741 | 0.008397 | 0.009552 |
| oren_c | 0.017878 | 0.017837 | 0.017637 | 0.018114 |
| oren_native | 0.031128 | 0.031153 | 0.030824 | 0.031533 |
| oren_obc | 0.015860 | 0.015920 | 0.015685 | 0.016234 |

Output checksum (stdout): `2995000000`
