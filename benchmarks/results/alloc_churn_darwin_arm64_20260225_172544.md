# alloc_churn benchmark (20260225_172544)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: b518e165c781173172cc2583b6aa257c44821ecb
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002684 | 0.002686 | 0.002629 | 0.002741 |
| oren_c | 0.012383 | 0.012339 | 0.012171 | 0.012442 |
| oren_native | 0.018295 | 0.018273 | 0.018084 | 0.018454 |
| oren_obc | 0.161768 | 0.162083 | 0.159929 | 0.163846 |

Output checksum (stdout): `199990000`
