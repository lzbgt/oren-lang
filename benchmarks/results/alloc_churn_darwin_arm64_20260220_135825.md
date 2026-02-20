# alloc_churn benchmark (20260220_135825)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: cea926edf266a03fe5c8080a4b90eb9c82168e01
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005934 | 0.005934 | 0.005934 | 0.005934 |
| oren_c | 0.030612 | 0.030612 | 0.030612 | 0.030612 |
| oren_native | 5.752321 | 5.752321 | 5.752321 | 5.752321 |
| oren_obc | 0.163068 | 0.163068 | 0.163068 | 0.163068 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 2048 | 1024 | 0 | 1024 | 0 |

Output checksum (stdout): `199990000`
