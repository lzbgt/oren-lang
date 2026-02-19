# alloc_churn benchmark (20260220_042046)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: f2fcc8abe0025a6cc88b3f20199669e9794e736c
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002660 | 0.002644 | 0.002575 | 0.002688 |
| oren_c | 0.030967 | 0.031106 | 0.030430 | 0.031772 |
| oren_native | 0.070210 | 0.070609 | 0.068116 | 0.072918 |
| oren_obc | 0.164351 | 0.164204 | 0.163424 | 0.164740 |

Output checksum (stdout): `199990000`
