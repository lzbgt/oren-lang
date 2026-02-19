# dot_product benchmark (20260219_092143)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: b60b69900edb8aecc8ae79fb5a5fdb95da66567f
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004739 | 0.004868 | 0.004668 | 0.005373 |
| oren_c | 0.017374 | 0.017572 | 0.017059 | 0.018182 |
| oren_native | 0.024605 | 0.024619 | 0.024434 | 0.024738 |
| oren_obc | 0.574263 | 0.575575 | 0.573787 | 0.578290 |

Output checksum (stdout): `507588000000`
