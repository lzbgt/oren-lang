# multi_list_push_int benchmark (20260219_104927)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: c3a4a3cbf6dcf9d206f4f8ac1bf11c93e3aff926
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008330 | 0.008370 | 0.008214 | 0.008506 |
| oren_c | 0.078622 | 0.078695 | 0.078287 | 0.079429 |
| oren_native | 0.030287 | 0.030239 | 0.029847 | 0.030448 |
| oren_obc | 1.219088 | 1.219589 | 1.216083 | 1.222608 |

Output checksum (stdout): `2995000000`
