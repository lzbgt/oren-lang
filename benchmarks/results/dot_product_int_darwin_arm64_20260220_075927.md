# dot_product_int benchmark (20260220_075927)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: c6cb0aff0200ac27da65aa9c26c579f2e8435a78
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.007476 | 0.007669 | 0.006222 | 0.010441 |
| oren_c | 0.019818 | 0.020992 | 0.017964 | 0.023888 |
| oren_native | 0.026845 | 0.027145 | 0.025365 | 0.029882 |
| oren_obc | 0.012192 | 0.011870 | 0.010742 | 0.012594 |

Output checksum (stdout): `507588000000`
