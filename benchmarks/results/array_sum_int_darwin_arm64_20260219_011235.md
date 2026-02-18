# array_sum_int benchmark (20260219_011235)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: c0027910c6a0c7ed204d876cfefd89b2485ccda1
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005875 | 0.006063 | 0.005715 | 0.006880 |
| oren_c | 0.203014 | 0.202823 | 0.202096 | 0.203820 |
| oren_native | 0.216745 | 0.216841 | 0.215877 | 0.217709 |
| oren_obc | 0.636095 | 0.636043 | 0.634654 | 0.637442 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17301504 | 17301504 | 17301504 | 17301504 |
| oren_c | 49741824 | 49738547 | 49725440 | 49741824 |
| oren_native | 17973248 | 17973248 | 17973248 | 17973248 |
| oren_obc | 70582272 | 70588825 | 70582272 | 70598656 |

Output checksum (stdout): `999000000`
