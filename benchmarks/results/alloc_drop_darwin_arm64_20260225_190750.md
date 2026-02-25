# alloc_drop benchmark (20260225_190750)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a3c06ecdb5368e072db5ddc09c1b151ebe8666c7
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002962 | 0.003028 | 0.002877 | 0.003192 |
| oren_c | 0.002495 | 0.002547 | 0.002448 | 0.002703 |
| oren_native | 0.006860 | 0.006891 | 0.006748 | 0.007054 |
| oren_obc | 0.003884 | 0.003897 | 0.003798 | 0.004034 |

Output checksum (stdout): `alloc_drop keep=11`
