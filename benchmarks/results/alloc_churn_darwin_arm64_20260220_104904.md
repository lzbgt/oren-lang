# alloc_churn benchmark (20260220_104904)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: ea30b50a2c9482a01f8485e45c0bc42944757135
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002611 | 0.002629 | 0.002552 | 0.002721 |
| oren_c | 0.030362 | 0.030491 | 0.030230 | 0.031044 |
| oren_native | 4.061595 | 4.062374 | 4.051791 | 4.079381 |
| oren_obc | 0.162835 | 0.163476 | 0.162401 | 0.166365 |

Output checksum (stdout): `199990000`
