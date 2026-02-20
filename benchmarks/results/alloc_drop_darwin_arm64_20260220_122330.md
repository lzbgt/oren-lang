# alloc_drop benchmark (20260220_122330)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a0033b496e44927210b31551a27e1d1e3c81627c
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002768 | 0.002761 | 0.002707 | 0.002811 |
| oren_c | 0.004469 | 0.004529 | 0.004434 | 0.004667 |
| oren_native | 0.146985 | 0.148416 | 0.145071 | 0.153598 |
| oren_obc | 0.006633 | 0.006637 | 0.006563 | 0.006739 |

Output checksum (stdout): `alloc_drop keep=11`
