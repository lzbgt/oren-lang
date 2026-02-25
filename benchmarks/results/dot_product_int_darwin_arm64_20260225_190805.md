# dot_product_int benchmark (20260225_190805)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a3c06ecdb5368e072db5ddc09c1b151ebe8666c7
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005270 | 0.005345 | 0.005205 | 0.005671 |
| oren_c | 0.012725 | 0.012736 | 0.012211 | 0.013127 |
| oren_native | 0.021602 | 0.021741 | 0.021304 | 0.022241 |
| oren_obc | 0.374764 | 0.374248 | 0.371333 | 0.377329 |

Output checksum (stdout): `507588000000`
