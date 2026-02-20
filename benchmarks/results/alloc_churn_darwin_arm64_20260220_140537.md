# alloc_churn benchmark (20260220_140537)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 9bf5bc9972a41042dab287dd4b77b9f0672c6742
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003126 | 0.003126 | 0.003126 | 0.003126 |
| oren_c | 0.030874 | 0.030874 | 0.030874 | 0.030874 |
| oren_native | 5.769215 | 5.769215 | 5.769215 | 5.769215 |
| oren_obc | 0.164425 | 0.164425 | 0.164425 | 0.164425 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 2048 | 1024 | 0 | 1024 | 0 |

Output checksum (stdout): `199990000`
