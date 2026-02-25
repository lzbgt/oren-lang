# array_sum_int benchmark (20260225_182541)

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
| c | 0.004187 | 0.004180 | 0.003893 | 0.004400 |
| oren_c | 0.008287 | 0.008235 | 0.007989 | 0.008564 |
| oren_native | 0.015893 | 0.015978 | 0.015680 | 0.016245 |
| oren_obc | 0.253903 | 0.254146 | 0.250999 | 0.257383 |

Output checksum (stdout): `999000000`
