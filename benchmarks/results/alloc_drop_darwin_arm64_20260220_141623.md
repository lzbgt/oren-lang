# alloc_drop benchmark (20260220_141623)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 9380ecca620e80dc396dee523f857d54b6330eae
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003418 | 0.003418 | 0.003418 | 0.003418 |
| oren_c | 0.005296 | 0.005296 | 0.005296 | 0.005296 |
| oren_native | 18.033928 | 18.033928 | 18.033928 | 18.033928 |
| oren_obc | 0.009221 | 0.009221 | 0.009221 | 0.009221 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 137 | 137 | 0 | 0 | 0 |

Output checksum (stdout): `alloc_drop keep=11`
