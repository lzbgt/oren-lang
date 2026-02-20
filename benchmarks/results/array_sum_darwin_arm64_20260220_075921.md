# array_sum benchmark (20260220_075921)

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
| c | 0.006063 | 0.006006 | 0.005544 | 0.006313 |
| oren_c | 0.036111 | 0.035751 | 0.034028 | 0.036571 |
| oren_native | 0.031073 | 0.031163 | 0.030765 | 0.031689 |
| oren_obc | 0.160097 | 0.163776 | 0.159453 | 0.174186 |

Output checksum (stdout): `999000000`
