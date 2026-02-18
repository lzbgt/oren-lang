# alloc_drop benchmark (20260219_002526)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0019373d6f61ff78e0bfdc6530183f2c9bf44c37
- runs: 3 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004736 | 0.004856 | 0.004665 | 0.005167 |
| oren_c | 0.007136 | 0.007030 | 0.006759 | 0.007194 |
| oren_native | 0.295077 | 0.294311 | 0.290142 | 0.297715 |
| oren_obc | 0.012466 | 0.012522 | 0.012109 | 0.012990 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 1327104 | 1327104 | 1327104 | 1327104 |
| oren_c | 4718592 | 4724053 | 4718592 | 4734976 |
| oren_native | 7749632 | 7749632 | 7749632 | 7749632 |
| oren_obc | 9355264 | 9360725 | 9355264 | 9371648 |

Output checksum (stdout): `alloc_drop keep=11`
