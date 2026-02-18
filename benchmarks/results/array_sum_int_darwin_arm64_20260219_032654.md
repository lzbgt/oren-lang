# array_sum_int benchmark (20260219_032654)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: f3fe9afc19e64fd8aefc265b0279232dc31639bb
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003789 | 0.003791 | 0.003663 | 0.003915 |
| oren_c | 0.069743 | 0.069604 | 0.069371 | 0.069765 |
| oren_native | 0.149658 | 0.149677 | 0.148514 | 0.150750 |
| oren_obc | 0.627914 | 0.628074 | 0.626368 | 0.631053 |

Output checksum (stdout): `999000000`
