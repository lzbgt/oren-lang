# alloc_drop benchmark (20260220_130131)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1432a55f89a21b3315be471d013bb7af274e43cf
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002771 | 0.002774 | 0.002684 | 0.002898 |
| oren_c | 0.004437 | 0.004532 | 0.004305 | 0.005050 |
| oren_native | 0.143877 | 0.144602 | 0.141896 | 0.148896 |
| oren_obc | 0.006633 | 0.006632 | 0.006603 | 0.006670 |

Output checksum (stdout): `alloc_drop keep=11`
