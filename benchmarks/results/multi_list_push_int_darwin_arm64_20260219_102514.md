# multi_list_push_int benchmark (20260219_102514)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 668a079888e4d234bae4375472d26ba8cf93f9d8
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.007987 | 0.008005 | 0.007894 | 0.008160 |
| oren_c | 0.077027 | 0.077194 | 0.076819 | 0.077727 |
| oren_native | 0.029887 | 0.029903 | 0.029565 | 0.030194 |
| oren_obc | 1.199537 | 1.201260 | 1.195784 | 1.211557 |

Output checksum (stdout): `2995000000`
