# alloc_drop benchmark (20260220_153459)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: e345252035963cc4aac2643c7eddc3e46cb078b4
- runs: 1 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002921 | 0.002921 | 0.002921 | 0.002921 |
| oren_c | 0.004492 | 0.004492 | 0.004492 | 0.004492 |
| oren_native | 0.175062 | 0.175062 | 0.175062 | 0.175062 |
| oren_obc | 0.006840 | 0.006840 | 0.006840 | 0.006840 |

Output checksum (stdout): `alloc_drop keep=11`
