# array_sum_int benchmark (20260219_020505)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 4fe78cecebca07fef042b244c399a1936c69fdcb
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003800 | 0.003869 | 0.003728 | 0.004182 |
| oren_c | 0.134909 | 0.135095 | 0.134448 | 0.136458 |
| oren_native | 0.210805 | 0.211110 | 0.210280 | 0.212128 |
| oren_obc | 0.648672 | 0.644775 | 0.624877 | 0.652042 |

Output checksum (stdout): `999000000`
