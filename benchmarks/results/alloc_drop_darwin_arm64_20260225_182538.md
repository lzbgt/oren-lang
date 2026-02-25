# alloc_drop benchmark (20260225_182538)

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
| c | 0.003218 | 0.003256 | 0.002924 | 0.003596 |
| oren_c | 0.002600 | 0.002700 | 0.002438 | 0.003051 |
| oren_native | 0.007466 | 0.007308 | 0.006688 | 0.007673 |
| oren_obc | 0.003987 | 0.004072 | 0.003844 | 0.004309 |

Output checksum (stdout): `alloc_drop keep=11`
