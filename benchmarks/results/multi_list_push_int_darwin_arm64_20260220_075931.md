# multi_list_push_int benchmark (20260220_075931)

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
| c | 0.012639 | 0.012897 | 0.010772 | 0.015318 |
| oren_c | 0.049279 | 0.048997 | 0.047763 | 0.050298 |
| oren_native | 0.032413 | 0.032434 | 0.032274 | 0.032578 |
| oren_obc | 0.014850 | 0.014767 | 0.014057 | 0.015423 |

Output checksum (stdout): `2995000000`
