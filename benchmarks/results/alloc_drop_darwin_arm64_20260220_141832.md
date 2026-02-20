# alloc_drop benchmark (20260220_141832)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 707d1db63544c22c31f933c655ac1665879ee6d5
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003195 | 0.003195 | 0.003195 | 0.003195 |
| oren_c | 0.005192 | 0.005192 | 0.005192 | 0.005192 |
| oren_native | 15.728585 | 15.728585 | 15.728585 | 15.728585 |
| oren_obc | 0.008092 | 0.008092 | 0.008092 | 0.008092 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 1428 | 1423 | 0 | 4 | 0 |

Output checksum (stdout): `alloc_drop keep=11`
