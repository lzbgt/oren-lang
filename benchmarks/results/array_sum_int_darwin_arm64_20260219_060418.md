# array_sum_int benchmark (20260219_060418)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 05654972c13598333b733ef850c452b2c9b27d14
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004008 | 0.004109 | 0.003841 | 0.004394 |
| oren_c | 0.057246 | 0.057445 | 0.057094 | 0.058013 |
| oren_native | 0.020166 | 0.020180 | 0.020060 | 0.020313 |
| oren_obc | 0.622126 | 0.622282 | 0.619642 | 0.626101 |

Output checksum (stdout): `999000000`
