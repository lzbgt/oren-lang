# alloc_churn benchmark (20260219_045329)

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
| c | 0.004082 | 0.004214 | 0.004004 | 0.004740 |
| oren_c | 0.069660 | 0.069966 | 0.068895 | 0.072238 |
| oren_native | 0.162040 | 0.162111 | 0.161809 | 0.162441 |
| oren_obc | 0.388069 | 0.388884 | 0.387041 | 0.392695 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 1294336 | 1294336 | 1294336 | 1294336 |
| oren_c | 68370432 | 68380262 | 68354048 | 68435968 |
| oren_native | 53788672 | 53788672 | 53788672 | 53788672 |
| oren_obc | 61358080 | 61371187 | 61358080 | 61390848 |

Output checksum (stdout): `199990000`
