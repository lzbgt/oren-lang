# alloc_churn benchmark (20260220_134105)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: e8a41da66c615466e7bf7d439586f22bb1187a6d
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003443 | 0.003443 | 0.003443 | 0.003443 |
| oren_c | 0.030767 | 0.030767 | 0.030767 | 0.030767 |
| oren_native | 5.034596 | 5.034596 | 5.034596 | 5.034596 |
| oren_obc | 0.165292 | 0.165292 | 0.165292 | 0.165292 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 2048 | 1024 | 0 | 1024 | 0 |

Output checksum (stdout): `199990000`
