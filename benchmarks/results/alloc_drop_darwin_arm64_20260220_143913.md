# alloc_drop benchmark (20260220_143913)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: bae69bcac6eabe436ce3e2ce45b4751e4f722f75
- runs: 1 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002761 | 0.002761 | 0.002761 | 0.002761 |
| oren_c | 0.004437 | 0.004437 | 0.004437 | 0.004437 |
| oren_native | 3.232325 | 3.232325 | 3.232325 | 3.232325 |
| oren_obc | 0.007368 | 0.007368 | 0.007368 | 0.007368 |

Output checksum (stdout): `alloc_drop keep=11`
