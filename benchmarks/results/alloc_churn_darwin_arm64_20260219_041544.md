# alloc_churn benchmark (20260219_041544)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 7ed08094fca7e89b239fef32f4e964fe0b0ecd77
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004221 | 0.004402 | 0.004104 | 0.005070 |
| oren_c | 0.069595 | 0.069587 | 0.069136 | 0.070090 |
| oren_native | 0.590617 | 0.590594 | 0.588108 | 0.592969 |
| oren_obc | 0.389425 | 0.389690 | 0.388843 | 0.391789 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 1294336 | 1294336 | 1294336 | 1294336 |
| oren_c | 68370432 | 68363878 | 68354048 | 68370432 |
| oren_native | 53821440 | 53821440 | 53821440 | 53821440 |
| oren_obc | 61358080 | 61371187 | 61358080 | 61407232 |

Output checksum (stdout): `199990000`
