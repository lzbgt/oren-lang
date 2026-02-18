# array_sum_int benchmark (20260219_055746)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 05bf1448f753cd99c83456dcc1916cc9be2d5071
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003957 | 0.004038 | 0.003900 | 0.004270 |
| oren_c | 0.065205 | 0.065338 | 0.065180 | 0.065878 |
| oren_native | 0.019772 | 0.019810 | 0.019714 | 0.019932 |
| oren_obc | 0.621473 | 0.621636 | 0.619705 | 0.623682 |

Output checksum (stdout): `999000000`
