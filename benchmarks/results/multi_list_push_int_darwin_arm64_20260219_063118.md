# multi_list_push_int benchmark (20260219_063118)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 6129ba79a72d82f386fa813e0f2ee90022d53e12
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008332 | 0.008454 | 0.008254 | 0.009037 |
| oren_c | 0.079237 | 0.079472 | 0.078551 | 0.080423 |
| oren_native | 0.030555 | 0.030480 | 0.030060 | 0.030914 |
| oren_obc | 1.228837 | 1.228091 | 1.226402 | 1.229895 |

Output checksum (stdout): `2995000000`
