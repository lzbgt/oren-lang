# dot_product benchmark (20260218_175058)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 5cfd0900e6ec10f2f0088fdf290f94b954839e7c
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004932 | 0.005069 | 0.004786 | 0.005550 |
| oren_c | 0.319124 | 0.316515 | 0.310311 | 0.321451 |
| oren_native | 0.219576 | 0.220461 | 0.218578 | 0.225790 |
| oren_obc | 0.902650 | 0.903560 | 0.902246 | 0.907555 |

Output checksum (stdout): `507588000000`
