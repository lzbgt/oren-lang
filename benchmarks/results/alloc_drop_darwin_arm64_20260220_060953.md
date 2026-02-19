# alloc_drop benchmark (20260220_060953)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 323c73cbc4f2185a21f51d76e4b148d3ca9a8c1b
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002840 | 0.002840 | 0.002811 | 0.002865 |
| oren_c | 0.004540 | 0.004542 | 0.004473 | 0.004630 |
| oren_native | 0.097831 | 0.096545 | 0.094139 | 0.098243 |
| oren_obc | 0.007399 | 0.007288 | 0.007036 | 0.007544 |

Output checksum (stdout): `alloc_drop keep=11
alloc_drop keep=11
alloc_drop keep=11
alloc_drop keep=11
alloc_drop keep=11`
