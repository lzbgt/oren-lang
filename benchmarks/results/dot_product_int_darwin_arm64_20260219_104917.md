# dot_product_int benchmark (20260219_104917)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: c3a4a3cbf6dcf9d206f4f8ac1bf11c93e3aff926
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005303 | 0.005352 | 0.005176 | 0.005560 |
| oren_c | 0.016875 | 0.016791 | 0.016588 | 0.016932 |
| oren_native | 0.024587 | 0.024780 | 0.024494 | 0.025341 |
| oren_obc | 0.555857 | 0.556509 | 0.554031 | 0.559956 |

Output checksum (stdout): `507588000000`
