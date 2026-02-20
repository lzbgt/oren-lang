# dot_product benchmark (20260220_075924)

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
| c | 0.006335 | 0.006395 | 0.006015 | 0.006942 |
| oren_c | 0.058914 | 0.060386 | 0.058294 | 0.067338 |
| oren_native | 0.063138 | 0.064437 | 0.061969 | 0.070124 |
| oren_obc | 0.288174 | 0.286143 | 0.274128 | 0.292319 |

Output checksum (stdout): `507588000000`
