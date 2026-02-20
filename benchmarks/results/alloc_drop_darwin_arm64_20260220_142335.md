# alloc_drop benchmark (20260220_142335)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: cb554a2ebab07336146d3adc484738429c8956db
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003250 | 0.003250 | 0.003250 | 0.003250 |
| oren_c | 0.005463 | 0.005463 | 0.005463 | 0.005463 |
| oren_native | 15.275372 | 15.275372 | 15.275372 | 15.275372 |
| oren_obc | 0.008667 | 0.008667 | 0.008667 | 0.008667 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 1422 | 1417 | 0 | 4 | 0 |

Output checksum (stdout): `alloc_drop keep=11`
