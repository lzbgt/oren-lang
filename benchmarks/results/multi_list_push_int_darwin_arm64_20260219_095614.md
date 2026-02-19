# multi_list_push_int benchmark (20260219_095614)

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
| c | 0.008257 | 0.008593 | 0.008221 | 0.009460 |
| oren_c | 0.078966 | 0.079829 | 0.078658 | 0.081488 |
| oren_native | 0.030238 | 0.030245 | 0.030155 | 0.030373 |
| oren_obc | 1.187840 | 1.188018 | 1.185567 | 1.191175 |

Output checksum (stdout): `2995000000`
