# array_sum_int benchmark (20260219_062648)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 60a51fc53eef5894cfb2aac11661fc0d7c7eb2e4
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004389 | 0.004274 | 0.003966 | 0.004563 |
| oren_c | 0.012024 | 0.012063 | 0.011893 | 0.012292 |
| oren_native | 0.020845 | 0.020735 | 0.020168 | 0.021318 |
| oren_obc | 0.621412 | 0.621411 | 0.619242 | 0.622751 |

Output checksum (stdout): `999000000`
