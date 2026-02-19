# array_sum_int benchmark (20260219_100111)

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
| c | 0.003800 | 0.003810 | 0.003719 | 0.003984 |
| oren_c | 0.011123 | 0.011134 | 0.010906 | 0.011418 |
| oren_native | 0.019881 | 0.019866 | 0.019660 | 0.020117 |
| oren_obc | 0.607553 | 0.607898 | 0.605575 | 0.610755 |

Output checksum (stdout): `999000000`
