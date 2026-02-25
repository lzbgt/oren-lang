# array_sum benchmark (20260225_182539)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a5bcb6b0274d4ba760da9b287e6a9d1b89d5872c
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004206 | 0.004333 | 0.004104 | 0.004745 |
| oren_c | 0.008016 | 0.008085 | 0.007999 | 0.008280 |
| oren_native | 0.015934 | 0.015856 | 0.015652 | 0.016058 |
| oren_obc | 0.255487 | 0.255550 | 0.253869 | 0.257843 |

Output checksum (stdout): `999000000`
