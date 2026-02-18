# array_sum_int benchmark (20260219_012921)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 490aad5f257ff9475f08bb250f62a44584fe795d
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005512 | 0.005702 | 0.005426 | 0.006229 |
| oren_c | 0.211641 | 0.212102 | 0.210693 | 0.213810 |
| oren_native | 0.214280 | 0.214560 | 0.213671 | 0.215721 |
| oren_obc | 0.629495 | 0.630675 | 0.629227 | 0.632638 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17301504 | 17301504 | 17301504 | 17301504 |
| oren_c | 49741824 | 49738547 | 49725440 | 49741824 |
| oren_native | 17973248 | 17973248 | 17973248 | 17973248 |
| oren_obc | 70582272 | 70588825 | 70582272 | 70598656 |

Output checksum (stdout): `999000000`
