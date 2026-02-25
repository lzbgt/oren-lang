# multi_list_sum benchmark (20260225_185736)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 44c0c215a0d1ea12fe55de5ddac1d121ebb9642d
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.010114 | 0.010140 | 0.009649 | 0.010516 |
| oren_c | 0.043653 | 0.043881 | 0.042949 | 0.045363 |
| oren_native | 0.030782 | 0.030835 | 0.030312 | 0.031475 |
| oren_obc | 0.553216 | 0.552610 | 0.548934 | 0.554726 |

Output checksum (stdout): `2995000000`
