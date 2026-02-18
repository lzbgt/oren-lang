# alloc_churn benchmark (20260219_044310)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1980a4851ae2269f1eea6db964bc41575b7da4b6
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004049 | 0.004188 | 0.003888 | 0.004865 |
| oren_c | 0.069804 | 0.069655 | 0.068937 | 0.070582 |
| oren_native | 0.396107 | 0.396554 | 0.395579 | 0.398721 |
| oren_obc | 0.387866 | 0.388580 | 0.387149 | 0.391745 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 1294336 | 1294336 | 1294336 | 1294336 |
| oren_c | 68370432 | 68367155 | 68354048 | 68370432 |
| oren_native | 53821440 | 53821440 | 53821440 | 53821440 |
| oren_obc | 61358080 | 61364633 | 61358080 | 61374464 |

Output checksum (stdout): `199990000`
