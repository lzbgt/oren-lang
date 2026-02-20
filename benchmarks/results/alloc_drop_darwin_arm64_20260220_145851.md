# alloc_drop benchmark (20260220_145851)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 2d751f1556d28ed38ca049d09521bd079b975d89
- runs: 1 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003028 | 0.003028 | 0.003028 | 0.003028 |
| oren_c | 0.004617 | 0.004617 | 0.004617 | 0.004617 |
| oren_native | 18.746595 | 18.746595 | 18.746595 | 18.746595 |
| oren_obc | 0.007593 | 0.007593 | 0.007593 | 0.007593 |

Output checksum (stdout): `alloc_drop keep=11`
