# array_sum_int benchmark (20260219_014449)

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
| c | 0.005551 | 0.005556 | 0.005157 | 0.005995 |
| oren_c | 0.136853 | 0.136796 | 0.136351 | 0.137283 |
| oren_native | 0.216751 | 0.217087 | 0.214180 | 0.222405 |
| oren_obc | 0.628840 | 0.630524 | 0.627838 | 0.634649 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17301504 | 17301504 | 17301504 | 17301504 |
| oren_c | 49479680 | 49479680 | 49479680 | 49479680 |
| oren_native | 17973248 | 17973248 | 17973248 | 17973248 |
| oren_obc | 70582272 | 70582272 | 70565888 | 70598656 |

Output checksum (stdout): `999000000`
