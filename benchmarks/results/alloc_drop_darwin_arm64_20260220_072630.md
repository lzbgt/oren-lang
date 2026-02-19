# alloc_drop benchmark (20260220_072630)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: adb813e9f6902370fd3c103af2d873d6f02782b5
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003082 | 0.003109 | 0.002971 | 0.003293 |
| oren_c | 0.005033 | 0.005006 | 0.004818 | 0.005167 |
| oren_native | 0.097255 | 0.097269 | 0.096189 | 0.098542 |
| oren_obc | 0.007602 | 0.007635 | 0.007413 | 0.008034 |

Output checksum (stdout): `alloc_drop keep=11`
