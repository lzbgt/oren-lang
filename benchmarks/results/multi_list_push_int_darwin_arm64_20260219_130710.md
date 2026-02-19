# multi_list_push_int benchmark (20260219_130710)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 7fefeb20df4e4072ad952a3e01dc99d71c06a8af
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008171 | 0.008220 | 0.008007 | 0.008429 |
| oren_c | 0.037124 | 0.037158 | 0.036704 | 0.037551 |
| oren_native | 0.030914 | 0.031036 | 0.030673 | 0.031513 |
| oren_obc | 0.011365 | 0.011397 | 0.011115 | 0.011844 |

Output checksum (stdout): `2995000000`
