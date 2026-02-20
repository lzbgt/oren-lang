# alloc_churn benchmark (20260220_142427)

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
| c | 0.003524 | 0.003524 | 0.003524 | 0.003524 |
| oren_c | 0.030452 | 0.030452 | 0.030452 | 0.030452 |
| oren_native | 10.281765 | 10.281765 | 10.281765 | 10.281765 |
| oren_obc | 0.162774 | 0.162774 | 0.162774 | 0.162774 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 9958 | 4979 | 0 | 4979 | 0 |

Output checksum (stdout): `199990000`
