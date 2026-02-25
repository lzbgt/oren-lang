# dot_product_int benchmark (20260225_182546)

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
| c | 0.005591 | 0.005636 | 0.005222 | 0.006098 |
| oren_c | 0.013092 | 0.013296 | 0.012720 | 0.014018 |
| oren_native | 0.022287 | 0.022358 | 0.022114 | 0.022829 |
| oren_obc | 0.375942 | 0.375196 | 0.371283 | 0.380216 |

Output checksum (stdout): `507588000000`
