# multi_list_sum benchmark (20260220_075932)

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
| c | 0.011053 | 0.011214 | 0.010263 | 0.012422 |
| oren_c | 0.085765 | 0.085431 | 0.079011 | 0.090582 |
| oren_native | 0.077992 | 0.078641 | 0.077099 | 0.082392 |
| oren_obc | 0.340814 | 0.347226 | 0.339938 | 0.363265 |

Output checksum (stdout): `2995000000`
