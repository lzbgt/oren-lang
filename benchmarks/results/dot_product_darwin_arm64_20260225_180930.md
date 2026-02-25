# dot_product benchmark (20260225_180930)

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
| c | 0.005124 | 0.005265 | 0.005046 | 0.005673 |
| oren_c | 0.015817 | 0.016289 | 0.014320 | 0.018474 |
| oren_native | 0.023575 | 0.023729 | 0.023049 | 0.024509 |
| oren_obc | 0.383419 | 0.384848 | 0.381077 | 0.391256 |

Output checksum (stdout): `507588000000`
