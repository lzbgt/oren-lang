# array_sum benchmark (20260219_182542)

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
| c | 0.004373 | 0.004442 | 0.004142 | 0.004954 |
| oren_c | 0.008249 | 0.008279 | 0.008074 | 0.008547 |
| oren_native | 0.015323 | 0.015288 | 0.015039 | 0.015534 |
| oren_obc | 0.009476 | 0.009654 | 0.009328 | 0.010511 |

Output checksum (stdout): `999000000`
