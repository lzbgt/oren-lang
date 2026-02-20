# alloc_drop benchmark (20260220_140749)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 65a166188707130d0d1c57a5dff117ff851e6825
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003578 | 0.003578 | 0.003578 | 0.003578 |
| oren_c | 0.005558 | 0.005558 | 0.005558 | 0.005558 |
| oren_native | 0.609344 | 0.609344 | 0.609344 | 0.609344 |
| oren_obc | 0.008438 | 0.008438 | 0.008438 | 0.008438 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 824 | 821 | 0 | 2 | 0 |

Output checksum (stdout): `alloc_drop keep=11`
