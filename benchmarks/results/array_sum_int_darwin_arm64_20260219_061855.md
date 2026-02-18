# array_sum_int benchmark (20260219_061855)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 220d7710401a332b5c660335e61a0662e44b9802
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003826 | 0.004017 | 0.003808 | 0.004445 |
| oren_c | 0.039121 | 0.039154 | 0.038928 | 0.039437 |
| oren_native | 0.019972 | 0.020057 | 0.019801 | 0.020629 |
| oren_obc | 0.620983 | 0.620755 | 0.619776 | 0.621871 |

Output checksum (stdout): `999000000`
