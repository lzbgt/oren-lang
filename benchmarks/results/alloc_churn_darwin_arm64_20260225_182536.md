# alloc_churn benchmark (20260225_182536)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a5bcb6b0274d4ba760da9b287e6a9d1b89d5872c
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003074 | 0.003131 | 0.002809 | 0.003596 |
| oren_c | 0.012725 | 0.012722 | 0.012603 | 0.012810 |
| oren_native | 0.018938 | 0.018950 | 0.018645 | 0.019413 |
| oren_obc | 0.162352 | 0.162579 | 0.160945 | 0.164326 |

Output checksum (stdout): `199990000`
