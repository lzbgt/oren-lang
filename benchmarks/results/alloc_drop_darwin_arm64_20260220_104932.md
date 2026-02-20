# alloc_drop benchmark (20260220_104932)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: ea30b50a2c9482a01f8485e45c0bc42944757135
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002805 | 0.002882 | 0.002686 | 0.003343 |
| oren_c | 0.004381 | 0.004438 | 0.004234 | 0.004842 |
| oren_native | 0.165469 | 0.164539 | 0.162427 | 0.166060 |
| oren_obc | 0.006619 | 0.006614 | 0.006540 | 0.006675 |

Output checksum (stdout): `alloc_drop keep=11`
