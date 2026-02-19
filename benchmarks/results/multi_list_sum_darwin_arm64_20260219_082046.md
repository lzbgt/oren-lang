# multi_list_sum benchmark (20260219_082046)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 3754489ef61d66c18d1ae8ee0c873f38a602cc14
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008178 | 0.008215 | 0.008087 | 0.008475 |
| oren_c | 0.183123 | 0.183138 | 0.182499 | 0.183656 |
| oren_native | 0.030481 | 0.030520 | 0.029912 | 0.031289 |
| oren_obc | 1.228275 | 1.228537 | 1.227505 | 1.229745 |

Output checksum (stdout): `2995000000`
