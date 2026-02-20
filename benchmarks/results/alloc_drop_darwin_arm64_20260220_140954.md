# alloc_drop benchmark (20260220_140954)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: e6c9928d774314a8b1ae3049b7be90fea262523e
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003516 | 0.003516 | 0.003516 | 0.003516 |
| oren_c | 0.005328 | 0.005328 | 0.005328 | 0.005328 |
| oren_native | 75.896875 | 75.896875 | 75.896875 | 75.896875 |
| oren_obc | 0.007736 | 0.007736 | 0.007736 | 0.007736 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 26 | 26 | 0 | 0 | 0 |

Output checksum (stdout): `alloc_drop keep=11`
