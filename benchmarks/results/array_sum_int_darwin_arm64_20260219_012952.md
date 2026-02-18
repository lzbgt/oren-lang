# array_sum_int benchmark (20260219_012952)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 490aad5f257ff9475f08bb250f62a44584fe795d
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005517 | 0.005568 | 0.005220 | 0.005890 |
| oren_c | 0.136518 | 0.136580 | 0.136161 | 0.137169 |
| oren_native | 0.215672 | 0.215241 | 0.213782 | 0.216107 |
| oren_obc | 0.629148 | 0.629517 | 0.628290 | 0.631888 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17301504 | 17301504 | 17301504 | 17301504 |
| oren_c | 49479680 | 49479680 | 49479680 | 49479680 |
| oren_native | 17973248 | 17973248 | 17973248 | 17973248 |
| oren_obc | 70598656 | 70592102 | 70582272 | 70598656 |

Output checksum (stdout): `999000000`
