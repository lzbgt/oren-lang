# array_sum benchmark (20260219_065305)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 191094fa29acc9d6b1377e7585220b816e7a3c8d
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003812 | 0.003835 | 0.003730 | 0.003950 |
| oren_c | 0.115891 | 0.116279 | 0.114592 | 0.118898 |
| oren_native | 0.143470 | 0.143351 | 0.142775 | 0.143683 |
| oren_obc | 0.622166 | 0.622652 | 0.620101 | 0.625791 |

Output checksum (stdout): `999000000`
