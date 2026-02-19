# multi_list_sum benchmark (20260219_223728)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0efd12524e37274075e0cb44e30fe4f484d861ea
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008512 | 0.008573 | 0.008293 | 0.009053 |
| oren_c | 0.018449 | 0.018572 | 0.018306 | 0.018950 |
| oren_native | 0.025475 | 0.025632 | 0.025204 | 0.026158 |
| oren_obc | 0.016364 | 0.016319 | 0.016030 | 0.016627 |

Output checksum (stdout): `2995000000`
