# array_sum_int benchmark (20260218_224358)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1557bd3e023e8007d19e94932be6bb4a656b4c88
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003995 | 0.004123 | 0.003851 | 0.004523 |
| oren_c | 0.201427 | 0.202717 | 0.200617 | 0.206138 |
| oren_native | 0.298886 | 0.299411 | 0.297769 | 0.301893 |
| oren_obc | 0.650686 | 0.652942 | 0.639931 | 0.673959 |

Output checksum (stdout): `999000000`
