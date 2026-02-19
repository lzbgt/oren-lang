# alloc_churn benchmark (20260220_060949)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 323c73cbc4f2185a21f51d76e4b148d3ca9a8c1b
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002689 | 0.002709 | 0.002639 | 0.002781 |
| oren_c | 0.032296 | 0.032181 | 0.031450 | 0.032503 |
| oren_native | 0.071029 | 0.069371 | 0.063842 | 0.071759 |
| oren_obc | 0.166316 | 0.165499 | 0.163900 | 0.166825 |

Output checksum (stdout): `199990000
199990000
199990000
199990000
199990000`
