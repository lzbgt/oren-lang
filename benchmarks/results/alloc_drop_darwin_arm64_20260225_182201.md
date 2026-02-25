# alloc_drop benchmark (20260225_182201)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1e81dc28a1d4d88d1e1ddc63949a1f6780bedd28
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003085 | 0.003199 | 0.002921 | 0.003593 |
| oren_c | 0.002717 | 0.002620 | 0.002425 | 0.002764 |
| oren_native | 0.007226 | 0.007246 | 0.007006 | 0.007517 |
| oren_obc | 0.004256 | 0.004183 | 0.003772 | 0.004643 |

Output checksum (stdout): `alloc_drop keep=11`
