# dot_product_int benchmark (20260225_180935)

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
| c | 0.005379 | 0.005401 | 0.005062 | 0.005665 |
| oren_c | 0.015720 | 0.015320 | 0.014404 | 0.016118 |
| oren_native | 0.023234 | 0.023167 | 0.022877 | 0.023372 |
| oren_obc | 0.378933 | 0.379107 | 0.376496 | 0.382653 |

Output checksum (stdout): `507588000000`
