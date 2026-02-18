# dot_product_int benchmark (20260219_002614)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0019373d6f61ff78e0bfdc6530183f2c9bf44c37
- runs: 3 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.007575 | 0.007430 | 0.006949 | 0.007766 |
| oren_c | 0.350895 | 0.352265 | 0.350067 | 0.355833 |
| oren_native | 0.394254 | 0.389288 | 0.374835 | 0.398776 |
| oren_obc | 0.917504 | 0.916531 | 0.913308 | 0.918781 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17317888 | 17323349 | 17317888 | 17334272 |
| oren_c | 97779712 | 97774250 | 97763328 | 97779712 |
| oren_native | 33964032 | 33964032 | 33964032 | 33964032 |
| oren_obc | 135757824 | 135752362 | 135741440 | 135757824 |

Output checksum (stdout): `507588000000`
