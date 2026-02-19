# dot_product_int benchmark (20260219_214654)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 15c770cde31e77fe5c8831cc0c67cef4827f038b
- runs: 3 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004846 | 0.004961 | 0.004767 | 0.005270 |
| oren_c | 0.012714 | 0.012755 | 0.012628 | 0.012924 |
| oren_native | 0.021315 | 0.021441 | 0.020981 | 0.022026 |
| oren_obc | 0.009865 | 0.009736 | 0.009448 | 0.009894 |

Output checksum (stdout): `507588000000`
