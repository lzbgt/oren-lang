# array_sum_int benchmark (20260219_014519)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 583c45635bcc7baacf4a3bdc1cfe8d977ef27f62
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005353 | 0.005353 | 0.005201 | 0.005458 |
| oren_c | 0.210958 | 0.211111 | 0.210370 | 0.211751 |
| oren_native | 0.213606 | 0.213712 | 0.212247 | 0.215388 |
| oren_obc | 0.629016 | 0.628827 | 0.626772 | 0.630585 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17301504 | 17301504 | 17301504 | 17301504 |
| oren_c | 49741824 | 49741824 | 49741824 | 49741824 |
| oren_native | 17973248 | 17973248 | 17973248 | 17973248 |
| oren_obc | 70582272 | 70592102 | 70582272 | 70615040 |

Output checksum (stdout): `999000000`
