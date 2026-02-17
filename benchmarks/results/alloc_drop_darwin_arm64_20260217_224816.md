# alloc_drop benchmark (20260217_224816)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 48a2c92f130c7a8e80e03d4e6dec2f390d727fa6
- runs: 3 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005587 | 0.005695 | 0.005172 | 0.006327 |
| oren_c | 0.007756 | 0.007817 | 0.007728 | 0.007967 |
| oren_native | 0.339068 | 0.338121 | 0.335598 | 0.339697 |
| oren_obc | 0.011808 | 0.011874 | 0.011670 | 0.012144 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 1327104 | 1321642 | 1310720 | 1327104 |
| oren_c | 4734976 | 4756821 | 4702208 | 4833280 |
| oren_native | 7733248 | 7733248 | 7733248 | 7733248 |
| oren_obc | 9355264 | 9355264 | 9355264 | 9355264 |

Output checksum (stdout): `alloc_drop keep=11`
