# alloc_churn benchmark (20260220_130107)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1432a55f89a21b3315be471d013bb7af274e43cf
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002661 | 0.002670 | 0.002590 | 0.002739 |
| oren_c | 0.029956 | 0.029996 | 0.029908 | 0.030105 |
| oren_native | 3.404138 | 3.403733 | 3.398245 | 3.409886 |
| oren_obc | 0.162944 | 0.163111 | 0.162606 | 0.164033 |

Output checksum (stdout): `199990000`
