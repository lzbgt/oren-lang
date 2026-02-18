# array_sum_int benchmark (20260219_011024)

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
| c | 0.005399 | 0.005543 | 0.005180 | 0.005974 |
| oren_c | 0.198690 | 0.198809 | 0.197806 | 0.200151 |
| oren_native | 0.216562 | 0.216065 | 0.212301 | 0.221369 |
| oren_obc | 0.624931 | 0.625193 | 0.624144 | 0.627029 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17301504 | 17298227 | 17285120 | 17301504 |
| oren_c | 49741824 | 49741824 | 49741824 | 49741824 |
| oren_native | 17973248 | 17973248 | 17973248 | 17973248 |
| oren_obc | 70582272 | 70533120 | 70336512 | 70582272 |

Output checksum (stdout): `999000000`
