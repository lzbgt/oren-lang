# alloc_churn benchmark (20260225_170359)

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
| c | 0.002827 | 0.002971 | 0.002735 | 0.003406 |
| oren_c | 0.012609 | 0.012718 | 0.012480 | 0.013106 |
| oren_native | 0.119364 | 0.120205 | 0.118327 | 0.122631 |
| oren_obc | 0.159332 | 0.160090 | 0.159086 | 0.162626 |

Output checksum (stdout): `199990000`
