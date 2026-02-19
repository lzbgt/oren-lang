# alloc_drop benchmark (20260220_041633)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 90f00be5c5876e1ca3d9bf25952a64fd20b91d61
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002857 | 0.002873 | 0.002737 | 0.003060 |
| oren_native | 0.109026 | 0.109862 | 0.107750 | 0.113194 |

Output checksum (stdout): `alloc_drop keep=11`
