# array_sum benchmark (20260219_070646)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 5e052d8ac66d1f175a45628bf26addfad9d2ae8f
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003726 | 0.003758 | 0.003635 | 0.003865 |
| oren_c | 0.114993 | 0.115283 | 0.114903 | 0.116027 |
| oren_native | 0.141615 | 0.141802 | 0.141476 | 0.142366 |
| oren_obc | 0.623170 | 0.624019 | 0.621843 | 0.628978 |

Output checksum (stdout): `999000000`
