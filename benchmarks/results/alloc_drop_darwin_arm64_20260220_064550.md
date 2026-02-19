# alloc_drop benchmark (20260220_064550)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: d5ef9aac4a3e38a2374662010901c1cb82496df5
- runs: 5 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002913 | 0.002968 | 0.002773 | 0.003423 |
| oren_c | 0.004688 | 0.004796 | 0.004603 | 0.005314 |
| oren_native | 0.097200 | 0.097666 | 0.096538 | 0.099099 |
| oren_obc | 0.007191 | 0.007471 | 0.006938 | 0.008976 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 10042 | 10011 | 0 | 31 | 0 |

Output checksum (stdout): `alloc_drop keep=11
alloc_drop keep=11
alloc_drop keep=11
alloc_drop keep=11
alloc_drop keep=11`
