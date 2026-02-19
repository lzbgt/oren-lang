# multi_list_sum benchmark (20260219_080946)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 017e72df9017534efd80f899668791945eb4295a
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008236 | 0.008384 | 0.008178 | 0.008927 |
| oren_c | 0.181982 | 0.181906 | 0.181454 | 0.182208 |
| oren_native | 0.030128 | 0.030143 | 0.030046 | 0.030293 |
| oren_obc | 1.228333 | 1.228230 | 1.225470 | 1.231959 |

Output checksum (stdout): `2995000000`
