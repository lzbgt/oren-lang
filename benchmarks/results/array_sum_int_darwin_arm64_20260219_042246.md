# array_sum_int benchmark (20260219_042246)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: c5a4366c772a88573efe672dfda7269c2a96b596
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003859 | 0.003924 | 0.003750 | 0.004210 |
| oren_c | 0.038750 | 0.038674 | 0.038108 | 0.039130 |
| oren_native | 0.020140 | 0.020230 | 0.020060 | 0.020446 |
| oren_obc | 0.627988 | 0.626637 | 0.622453 | 0.628578 |

Output checksum (stdout): `999000000`
