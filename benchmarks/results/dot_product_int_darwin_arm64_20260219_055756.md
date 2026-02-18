# dot_product_int benchmark (20260219_055756)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 05bf1448f753cd99c83456dcc1916cc9be2d5071
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004641 | 0.004781 | 0.004594 | 0.005318 |
| oren_c | 0.126783 | 0.126823 | 0.125859 | 0.127746 |
| oren_native | 0.024480 | 0.024489 | 0.024333 | 0.024764 |
| oren_obc | 0.889601 | 0.889591 | 0.887886 | 0.891161 |

Output checksum (stdout): `507588000000`
