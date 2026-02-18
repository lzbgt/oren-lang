# array_sum_int benchmark (20260219_011808)

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
| c | 0.005880 | 0.005843 | 0.005404 | 0.006565 |
| oren_c | 0.134493 | 0.134613 | 0.133836 | 0.135446 |
| oren_native | 0.215522 | 0.215816 | 0.214986 | 0.217261 |
| oren_obc | 0.632024 | 0.631937 | 0.630150 | 0.634366 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17301504 | 17298227 | 17285120 | 17301504 |
| oren_c | 49479680 | 49479680 | 49479680 | 49479680 |
| oren_native | 17973248 | 17973248 | 17973248 | 17973248 |
| oren_obc | 70598656 | 70598656 | 70582272 | 70615040 |

Output checksum (stdout): `999000000`
