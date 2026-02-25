# dot_product_int benchmark (20260225_185720)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 44c0c215a0d1ea12fe55de5ddac1d121ebb9642d
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005808 | 0.005860 | 0.005531 | 0.006213 |
| oren_c | 0.015907 | 0.015812 | 0.015478 | 0.016238 |
| oren_native | 0.024248 | 0.024249 | 0.023644 | 0.024860 |
| oren_obc | 0.392346 | 0.392647 | 0.391006 | 0.395704 |

Output checksum (stdout): `507588000000`
