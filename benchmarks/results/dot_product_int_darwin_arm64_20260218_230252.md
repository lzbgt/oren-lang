# dot_product_int benchmark (20260218_230252)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 3c43d9fa5b0caf158aab2dd2261126ce95847a72
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005412 | 0.005495 | 0.005216 | 0.005905 |
| oren_c | 0.342177 | 0.342343 | 0.341638 | 0.343361 |
| oren_native | 0.377566 | 0.377476 | 0.376721 | 0.378126 |
| oren_obc | 0.942356 | 0.942740 | 0.941374 | 0.944425 |

Output checksum (stdout): `507588000000`
