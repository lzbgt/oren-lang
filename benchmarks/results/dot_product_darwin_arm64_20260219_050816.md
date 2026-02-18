# dot_product benchmark (20260219_050816)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 5da2243f97a31a8c0a993e91bd3f9f6dcc0527a5
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.006472 | 0.006603 | 0.006359 | 0.007016 |
| oren_c | 0.209131 | 0.208262 | 0.206101 | 0.209745 |
| oren_native | 0.221092 | 0.221265 | 0.220930 | 0.221850 |
| oren_obc | 0.896550 | 0.903565 | 0.892125 | 0.937107 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17350656 | 17350656 | 17350656 | 17350656 |
| oren_c | 153157632 | 153157632 | 153157632 | 153157632 |
| oren_native | 67502080 | 67502080 | 67502080 | 67502080 |
| oren_obc | 135757824 | 135757824 | 135757824 | 135757824 |

Output checksum (stdout): `507588000000`
