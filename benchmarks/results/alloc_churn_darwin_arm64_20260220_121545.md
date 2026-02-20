# alloc_churn benchmark (20260220_121545)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 8d5cb1abe24f680a35de01727ce79f2dc0722c79
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002638 | 0.002632 | 0.002544 | 0.002717 |
| oren_c | 0.030081 | 0.030117 | 0.030050 | 0.030274 |
| oren_native | 3.408605 | 3.409528 | 3.402555 | 3.415113 |
| oren_obc | 0.162760 | 0.163415 | 0.162371 | 0.165136 |

Output checksum (stdout): `199990000`
