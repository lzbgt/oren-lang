# alloc_drop benchmark (20260220_130750)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 42583193fbec19df25ab51bbdd36dada84c0c1a1
- runs: 5 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002844 | 0.002847 | 0.002810 | 0.002899 |
| oren_c | 0.004615 | 0.004747 | 0.004414 | 0.005171 |
| oren_native | 0.173403 | 0.173495 | 0.172768 | 0.174535 |
| oren_obc | 0.006768 | 0.006779 | 0.006664 | 0.006962 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 1800 | 1794 | 0 | 6 | 0 |

Output checksum (stdout): `alloc_drop keep=11
alloc_drop keep=11
alloc_drop keep=11
alloc_drop keep=11
alloc_drop keep=11`
