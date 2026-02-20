# alloc_drop benchmark (20260220_115236)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: d9d1a21460677eefcf34e3c9e7358cf36d39e158
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003058 | 0.003058 | 0.003058 | 0.003058 |
| oren_c | 0.005393 | 0.005393 | 0.005393 | 0.005393 |
| oren_native | 0.165968 | 0.165968 | 0.165968 | 0.165968 |
| oren_obc | 0.008658 | 0.008658 | 0.008658 | 0.008658 |

Output checksum (stdout): `alloc_drop keep=11`
