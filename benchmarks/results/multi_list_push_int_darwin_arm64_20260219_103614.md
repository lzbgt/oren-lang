# multi_list_push_int benchmark (20260219_103614)

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
| c | 0.008312 | 0.008459 | 0.008253 | 0.008865 |
| oren_c | 0.080861 | 0.081042 | 0.080264 | 0.081962 |
| oren_native | 0.030877 | 0.030837 | 0.029951 | 0.031625 |
| oren_obc | 1.216925 | 1.234692 | 1.199536 | 1.280984 |

Output checksum (stdout): `2995000000`
