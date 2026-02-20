# alloc_churn benchmark (20260220_122103)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 71a8acbb54c6cf7cd8f5c8971b12c80725f1e3db
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002611 | 0.002689 | 0.002525 | 0.003042 |
| oren_c | 0.030029 | 0.030399 | 0.029952 | 0.031969 |
| oren_native | 3.643115 | 3.642665 | 3.637479 | 3.647549 |
| oren_obc | 0.162510 | 0.163296 | 0.161703 | 0.165216 |

Output checksum (stdout): `199990000`
