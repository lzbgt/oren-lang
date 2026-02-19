# array_sum_int benchmark (20260219_113013)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: bcb4bd9c7ae6c8dd7c3fd630d9551bc27c91ce4f
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004311 | 0.004458 | 0.004129 | 0.005073 |
| oren_c | 0.012183 | 0.012198 | 0.011600 | 0.012598 |
| oren_native | 0.021544 | 0.021425 | 0.021082 | 0.021693 |
| oren_obc | 0.010703 | 0.010729 | 0.010325 | 0.011357 |

Output checksum (stdout): `999000000`
