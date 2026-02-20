# alloc_drop benchmark (20260220_124816)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: e0762ee74bc28673e3628c6da05113eeef2644d5
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002850 | 0.002905 | 0.002734 | 0.003316 |
| oren_c | 0.004411 | 0.004416 | 0.004374 | 0.004495 |
| oren_native | 0.144678 | 0.144723 | 0.144181 | 0.145419 |
| oren_obc | 0.006697 | 0.006701 | 0.006605 | 0.006867 |

Output checksum (stdout): `alloc_drop keep=11`
