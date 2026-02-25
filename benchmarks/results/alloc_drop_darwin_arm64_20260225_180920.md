# alloc_drop benchmark (20260225_180920)

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
| c | 0.003031 | 0.003000 | 0.002900 | 0.003119 |
| oren_c | 0.002483 | 0.002464 | 0.002324 | 0.002598 |
| oren_native | 0.007076 | 0.007064 | 0.006868 | 0.007296 |
| oren_obc | 0.004004 | 0.004133 | 0.003906 | 0.004390 |

Output checksum (stdout): `alloc_drop keep=11`
