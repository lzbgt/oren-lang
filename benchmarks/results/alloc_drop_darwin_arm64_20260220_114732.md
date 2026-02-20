# alloc_drop benchmark (20260220_114732)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: f57052ccc958f24ada3c6ea0ff00dce8f8865ac1
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003187 | 0.003187 | 0.003187 | 0.003187 |
| oren_c | 0.005665 | 0.005665 | 0.005665 | 0.005665 |
| oren_native | 0.170685 | 0.170685 | 0.170685 | 0.170685 |
| oren_obc | 0.008712 | 0.008712 | 0.008712 | 0.008712 |

Output checksum (stdout): `alloc_drop keep=11`
