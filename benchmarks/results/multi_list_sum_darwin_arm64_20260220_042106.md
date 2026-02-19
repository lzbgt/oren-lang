# multi_list_sum benchmark (20260220_042106)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: f2fcc8abe0025a6cc88b3f20199669e9794e736c
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008371 | 0.008440 | 0.008276 | 0.008635 |
| oren_c | 0.017091 | 0.017160 | 0.016837 | 0.017477 |
| oren_native | 0.026359 | 0.026339 | 0.026026 | 0.026764 |
| oren_obc | 0.015274 | 0.015147 | 0.014791 | 0.015393 |

Output checksum (stdout): `2995000000`
