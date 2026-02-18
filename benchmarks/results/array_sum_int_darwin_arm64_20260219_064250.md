# array_sum_int benchmark (20260219_064250)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a8e448776d4a082a094b95f1f38e04e7a04eabfc
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003855 | 0.004140 | 0.003774 | 0.005336 |
| oren_c | 0.011250 | 0.011363 | 0.011118 | 0.011662 |
| oren_native | 0.020406 | 0.020386 | 0.020155 | 0.020572 |
| oren_obc | 0.622709 | 0.622841 | 0.621565 | 0.624855 |

Output checksum (stdout): `999000000`
