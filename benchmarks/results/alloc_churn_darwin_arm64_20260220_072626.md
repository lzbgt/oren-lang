# alloc_churn benchmark (20260220_072626)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: adb813e9f6902370fd3c103af2d873d6f02782b5
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002886 | 0.002901 | 0.002796 | 0.003035 |
| oren_c | 0.032089 | 0.032159 | 0.031626 | 0.032941 |
| oren_native | 0.071286 | 0.071102 | 0.067251 | 0.075934 |
| oren_obc | 0.169706 | 0.169674 | 0.167935 | 0.171603 |

Output checksum (stdout): `199990000`
