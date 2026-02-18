# array_sum_int benchmark (20260219_034125)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: bc32871e7dfafda94dc9d64bfc661422c7a3f1a8
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003885 | 0.003910 | 0.003803 | 0.004155 |
| oren_c | 0.038837 | 0.038915 | 0.038618 | 0.039486 |
| oren_native | 0.150526 | 0.150337 | 0.148788 | 0.151429 |
| oren_obc | 0.628100 | 0.628357 | 0.626880 | 0.629834 |

Output checksum (stdout): `999000000`
