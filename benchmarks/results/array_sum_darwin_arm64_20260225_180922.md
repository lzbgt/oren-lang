# array_sum benchmark (20260225_180922)

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
| c | 0.003928 | 0.004095 | 0.003905 | 0.004607 |
| oren_c | 0.009107 | 0.009092 | 0.008524 | 0.009558 |
| oren_native | 0.016459 | 0.016521 | 0.015859 | 0.017170 |
| oren_obc | 0.257807 | 0.258263 | 0.254827 | 0.261123 |

Output checksum (stdout): `999000000`
