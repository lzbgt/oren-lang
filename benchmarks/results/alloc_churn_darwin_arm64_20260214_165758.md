# alloc_churn benchmark (20260214_165758)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: d865fb2b2b2082a02e0e8dcc66f5b8106a283e7d
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002779 | 0.002889 | 0.002645 | 0.003176 |
| oren_c | 0.107799 | 0.107798 | 0.107534 | 0.108067 |
| oren_native | 0.570428 | 0.571212 | 0.567745 | 0.577552 |
| oren_obc | 0.387340 | 0.387991 | 0.386680 | 0.389814 |

Output checksum (stdout): `199990000`
