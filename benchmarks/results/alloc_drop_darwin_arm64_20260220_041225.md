# alloc_drop benchmark (20260220_041225)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 16a37ebfa6c1f5c80769bb3fcd275abb2dea1fc0
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002939 | 0.002943 | 0.002850 | 0.003045 |
| oren_native | 0.112454 | 0.110920 | 0.103597 | 0.114181 |

Output checksum (stdout): `alloc_drop keep=11`
