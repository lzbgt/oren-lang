# alloc_churn benchmark (20260220_130727)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 42583193fbec19df25ab51bbdd36dada84c0c1a1
- runs: 5 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002666 | 0.002779 | 0.002631 | 0.003109 |
| oren_c | 0.030365 | 0.030426 | 0.030133 | 0.030966 |
| oren_native | 4.214412 | 4.211078 | 4.204489 | 4.217130 |
| oren_obc | 0.163393 | 0.164050 | 0.162642 | 0.166154 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 10239 | 5119 | 0 | 5119 | 0 |

Output checksum (stdout): `199990000
199990000
199990000
199990000
199990000`
