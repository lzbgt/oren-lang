# array_sum_int benchmark (20260219_035636)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1f2f09f441d087161562e03f9e9fab1f6d9cbd92
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004004 | 0.004066 | 0.003771 | 0.004404 |
| oren_c | 0.039389 | 0.039340 | 0.039038 | 0.039618 |
| oren_native | 0.040908 | 0.040927 | 0.040707 | 0.041094 |
| oren_obc | 0.629024 | 0.628788 | 0.627231 | 0.630875 |

Output checksum (stdout): `999000000`
