# dot_product_int benchmark (20260219_061903)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 220d7710401a332b5c660335e61a0662e44b9802
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005128 | 0.005078 | 0.004579 | 0.005366 |
| oren_c | 0.072759 | 0.073004 | 0.072021 | 0.073790 |
| oren_native | 0.024895 | 0.024731 | 0.024316 | 0.024993 |
| oren_obc | 0.893882 | 0.893997 | 0.888133 | 0.901264 |

Output checksum (stdout): `507588000000`
