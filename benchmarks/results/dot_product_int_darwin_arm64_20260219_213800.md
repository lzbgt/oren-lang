# dot_product_int benchmark (20260219_213800)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 8b2869ae279b481e4148898008535860b955b8d3
- runs: 3 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005026 | 0.004960 | 0.004815 | 0.005039 |
| oren_c | 0.013123 | 0.013325 | 0.013072 | 0.013781 |
| oren_native | 0.025812 | 0.025795 | 0.025641 | 0.025933 |
| oren_obc | 0.009308 | 0.009265 | 0.009166 | 0.009323 |

Output checksum (stdout): `507588000000`
