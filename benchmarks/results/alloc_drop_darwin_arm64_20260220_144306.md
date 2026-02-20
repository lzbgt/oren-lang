# alloc_drop benchmark (20260220_144306)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 56538c0e7fc8af807509a88c46c2818d20c52b88
- runs: 1 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002759 | 0.002759 | 0.002759 | 0.002759 |
| oren_c | 0.004518 | 0.004518 | 0.004518 | 0.004518 |
| oren_native | 3.199475 | 3.199475 | 3.199475 | 3.199475 |
| oren_obc | 0.006864 | 0.006864 | 0.006864 | 0.006864 |

Output checksum (stdout): `alloc_drop keep=11`
