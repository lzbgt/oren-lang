# array_sum_int benchmark (20260219_182544)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 2f7eccd9123d38fda04388891f271292a8414a9e
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004536 | 0.004473 | 0.004264 | 0.004617 |
| oren_c | 0.008206 | 0.008076 | 0.007708 | 0.008359 |
| oren_native | 0.020735 | 0.021163 | 0.020234 | 0.023086 |
| oren_obc | 0.005258 | 0.005410 | 0.005235 | 0.005686 |

Output checksum (stdout): `999000000`
