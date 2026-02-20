# alloc_churn benchmark (20260220_075918)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: c6cb0aff0200ac27da65aa9c26c579f2e8435a78
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003726 | 0.003670 | 0.003451 | 0.003931 |
| oren_c | 0.036602 | 0.036593 | 0.035557 | 0.037941 |
| oren_native | 0.078430 | 0.077991 | 0.073134 | 0.081666 |
| oren_obc | 0.181752 | 0.183705 | 0.180783 | 0.188342 |

Output checksum (stdout): `199990000`
