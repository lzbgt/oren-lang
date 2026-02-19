# dot_product benchmark (20260219_182538)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 2f7eccd9123d38fda04388891f271292a8414a9e
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005504 | 0.005521 | 0.004916 | 0.006272 |
| oren_c | 0.012386 | 0.012635 | 0.012246 | 0.013348 |
| oren_native | 0.025312 | 0.025207 | 0.024769 | 0.025552 |
| oren_obc | 0.012369 | 0.012334 | 0.011964 | 0.012526 |

Output checksum (stdout): `507588000000`
