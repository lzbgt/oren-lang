# multi_list_sum benchmark (20260220_105049)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: ea30b50a2c9482a01f8485e45c0bc42944757135
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008487 | 0.008469 | 0.008241 | 0.008682 |
| oren_c | 0.068362 | 0.068426 | 0.068125 | 0.068867 |
| oren_native | 9.308602 | 9.310096 | 9.293195 | 9.331714 |
| oren_obc | 0.312384 | 0.313450 | 0.311423 | 0.318090 |

Output checksum (stdout): `2995000000`
