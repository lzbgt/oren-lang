# array_sum_int benchmark (20260219_053538)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 4ef4b12a7c9a9dd7fdf45fae3b4c203e86091c6a
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003749 | 0.003775 | 0.003663 | 0.003896 |
| oren_c | 0.081959 | 0.081896 | 0.081313 | 0.082304 |
| oren_native | 0.102534 | 0.102688 | 0.101885 | 0.103800 |
| oren_obc | 0.621127 | 0.622303 | 0.619036 | 0.626649 |

Output checksum (stdout): `999000000`
