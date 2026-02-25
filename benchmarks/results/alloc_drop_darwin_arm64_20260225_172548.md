# alloc_drop benchmark (20260225_172548)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: b518e165c781173172cc2583b6aa257c44821ecb
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002971 | 0.002987 | 0.002828 | 0.003195 |
| oren_c | 0.005544 | 0.005206 | 0.004544 | 0.005747 |
| oren_native | 0.149707 | 0.149977 | 0.148260 | 0.151903 |
| oren_obc | 0.007813 | 0.007803 | 0.007641 | 0.007967 |

Output checksum (stdout): `alloc_drop keep=11`
