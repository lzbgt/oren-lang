# multi_list_sum benchmark (20260220_162900)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: eb664191806e0b3565f2f21b20891a8e22aaa9f8
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008649 | 0.008673 | 0.008483 | 0.008929 |
| oren_c | 0.038789 | 0.038799 | 0.038308 | 0.039434 |
| oren_native | 0.026920 | 0.026907 | 0.026381 | 0.027376 |
| oren_obc | 0.305721 | 0.305932 | 0.304887 | 0.307831 |

Output checksum (stdout): `2995000000`
