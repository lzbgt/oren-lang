# alloc_churn benchmark (20260220_064546)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: d5ef9aac4a3e38a2374662010901c1cb82496df5
- runs: 5 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002697 | 0.002740 | 0.002617 | 0.003028 |
| oren_c | 0.032815 | 0.032989 | 0.031852 | 0.035079 |
| oren_native | 0.075680 | 0.076638 | 0.071560 | 0.083370 |
| oren_obc | 0.170757 | 0.171150 | 0.170197 | 0.172495 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 40000 | 20000 | 0 | 20000 | 0 |

Output checksum (stdout): `199990000
199990000
199990000
199990000
199990000`
