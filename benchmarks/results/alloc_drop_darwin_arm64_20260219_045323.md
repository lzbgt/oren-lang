# alloc_drop benchmark (20260219_045323)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 6dc533ea8737a3408832c4c11dbe321493d932b9
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004179 | 0.004314 | 0.004031 | 0.004820 |
| oren_c | 0.006641 | 0.006617 | 0.006526 | 0.006683 |
| oren_native | 0.103303 | 0.102509 | 0.099386 | 0.104322 |
| oren_obc | 0.011457 | 0.011349 | 0.010820 | 0.011722 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 1327104 | 1327104 | 1327104 | 1327104 |
| oren_c | 4472832 | 4469555 | 4456448 | 4472832 |
| oren_native | 7749632 | 7749632 | 7749632 | 7749632 |
| oren_obc | 9338880 | 9342156 | 9338880 | 9355264 |

Output checksum (stdout): `alloc_drop keep=11`
