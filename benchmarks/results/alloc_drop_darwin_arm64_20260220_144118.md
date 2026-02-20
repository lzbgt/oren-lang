# alloc_drop benchmark (20260220_144118)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a419ec0aa14a714f8cf826addd14be4b6b1e9ac5
- runs: 1 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002760 | 0.002760 | 0.002760 | 0.002760 |
| oren_c | 0.004488 | 0.004488 | 0.004488 | 0.004488 |
| oren_native | 3.259288 | 3.259288 | 3.259288 | 3.259288 |
| oren_obc | 0.007270 | 0.007270 | 0.007270 | 0.007270 |

Output checksum (stdout): `alloc_drop keep=11`
