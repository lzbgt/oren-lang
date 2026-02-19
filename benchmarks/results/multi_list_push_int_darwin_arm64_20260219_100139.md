# multi_list_push_int benchmark (20260219_100139)

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
| c | 0.008290 | 0.008323 | 0.008236 | 0.008497 |
| oren_c | 0.078916 | 0.079087 | 0.078661 | 0.079890 |
| oren_native | 0.030080 | 0.030125 | 0.030017 | 0.030253 |
| oren_obc | 1.188504 | 1.188171 | 1.185200 | 1.192817 |

Output checksum (stdout): `2995000000`
