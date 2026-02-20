# alloc_drop benchmark (20260220_075920)

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
| c | 0.003226 | 0.003323 | 0.003138 | 0.003637 |
| oren_c | 0.005474 | 0.005778 | 0.005294 | 0.006738 |
| oren_native | 0.108412 | 0.107907 | 0.105474 | 0.109669 |
| oren_obc | 0.008235 | 0.008217 | 0.007727 | 0.008662 |

Output checksum (stdout): `alloc_drop keep=11`
