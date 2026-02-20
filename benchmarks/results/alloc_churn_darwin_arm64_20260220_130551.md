# alloc_churn benchmark (20260220_130551)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0e8efeb26cf6726d422513b1a0bc00d0943eb11e
- runs: 5 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002649 | 0.002698 | 0.002615 | 0.002875 |
| oren_c | 0.030645 | 0.030878 | 0.030542 | 0.031415 |
| oren_native | 3.758490 | 3.755864 | 3.747822 | 3.761984 |
| oren_obc | 0.163992 | 0.164106 | 0.162719 | 0.166418 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 40000 | 20000 | 0 | 20000 | 0 |

Output checksum (stdout): `199990000
199990000
199990000
199990000
199990000`
