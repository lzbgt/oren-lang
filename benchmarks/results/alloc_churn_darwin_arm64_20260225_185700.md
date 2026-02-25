# alloc_churn benchmark (20260225_185700)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 44c0c215a0d1ea12fe55de5ddac1d121ebb9642d
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003553 | 0.003630 | 0.003318 | 0.004130 |
| oren_c | 0.015366 | 0.015376 | 0.014784 | 0.016071 |
| oren_native | 0.021318 | 0.021675 | 0.021011 | 0.023001 |
| oren_obc | 0.169609 | 0.170386 | 0.167545 | 0.176053 |

Output checksum (stdout): `199990000`
