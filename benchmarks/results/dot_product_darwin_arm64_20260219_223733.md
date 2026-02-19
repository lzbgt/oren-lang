# dot_product benchmark (20260219_223733)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0efd12524e37274075e0cb44e30fe4f484d861ea
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004967 | 0.004941 | 0.004807 | 0.005033 |
| oren_c | 0.013336 | 0.013418 | 0.013198 | 0.013835 |
| oren_native | 0.025120 | 0.025179 | 0.024552 | 0.026059 |
| oren_obc | 0.013010 | 0.013054 | 0.012762 | 0.013512 |

Output checksum (stdout): `507588000000`
