# dot_product benchmark (20260219_091521)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: ecc530306d641904303f9c7a3bff866c62fc0b00
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004907 | 0.004856 | 0.004699 | 0.005040 |
| oren_c | 0.017621 | 0.017615 | 0.017438 | 0.017799 |
| oren_native | 0.024677 | 0.024882 | 0.024443 | 0.025607 |
| oren_obc | 0.586239 | 0.585737 | 0.582615 | 0.590039 |

Output checksum (stdout): `507588000000`
