# array_sum_int benchmark (20260225_180926)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: b5b14c484ce0df6f7ed4eb76b20242c9fa0e6e22
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004485 | 0.004320 | 0.003900 | 0.004532 |
| oren_c | 0.009067 | 0.008769 | 0.008068 | 0.009245 |
| oren_native | 0.016057 | 0.016172 | 0.015661 | 0.017108 |
| oren_obc | 0.255912 | 0.256670 | 0.255059 | 0.259761 |

Output checksum (stdout): `999000000`
