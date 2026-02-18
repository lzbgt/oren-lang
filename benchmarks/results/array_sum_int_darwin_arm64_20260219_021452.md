# array_sum_int benchmark (20260219_021452)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: dae2f5d2bf2a40b1344d3eaa80ed1617992553fd
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003837 | 0.003802 | 0.003649 | 0.003892 |
| oren_c | 0.119732 | 0.120022 | 0.119213 | 0.121439 |
| oren_native | 0.211215 | 0.210957 | 0.210145 | 0.211676 |
| oren_obc | 0.627373 | 0.627570 | 0.623663 | 0.631059 |

Output checksum (stdout): `999000000`
