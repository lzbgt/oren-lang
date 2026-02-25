# array_sum_int benchmark (20260225_190756)

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
| c | 0.004099 | 0.004157 | 0.003956 | 0.004542 |
| oren_c | 0.007589 | 0.007560 | 0.007428 | 0.007684 |
| oren_native | 0.016575 | 0.016554 | 0.016178 | 0.016906 |
| oren_obc | 0.253680 | 0.254308 | 0.250797 | 0.257134 |

Output checksum (stdout): `999000000`
