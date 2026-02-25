# alloc_drop benchmark (20260225_170403)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0cb0c20c6d9a1428a0b84a8ed546f23b64d3d1f9
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003003 | 0.003037 | 0.002958 | 0.003166 |
| oren_c | 0.004724 | 0.004725 | 0.004677 | 0.004786 |
| oren_native | 0.151403 | 0.150325 | 0.146808 | 0.154349 |
| oren_obc | 0.007685 | 0.007610 | 0.007159 | 0.007876 |

Output checksum (stdout): `alloc_drop keep=11`
