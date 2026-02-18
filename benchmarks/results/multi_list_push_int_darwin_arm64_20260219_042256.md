# multi_list_push_int benchmark (20260219_042256)

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
| c | 0.007908 | 0.007966 | 0.007674 | 0.008297 |
| oren_c | 0.162481 | 0.162529 | 0.162014 | 0.163336 |
| oren_native | 0.030243 | 0.030215 | 0.029922 | 0.030536 |
| oren_obc | 1.239112 | 1.239557 | 1.237610 | 1.241919 |

Output checksum (stdout): `2995000000`
