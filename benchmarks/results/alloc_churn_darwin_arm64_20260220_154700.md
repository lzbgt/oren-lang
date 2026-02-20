# alloc_churn benchmark (20260220_154700)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 261ccbd932ead1966530978f5ff71a2e56181510
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002706 | 0.002744 | 0.002565 | 0.003066 |
| oren_c | 0.030406 | 0.030431 | 0.029971 | 0.030839 |
| oren_native | 0.131451 | 0.131486 | 0.129081 | 0.135081 |
| oren_obc | 0.164121 | 0.164076 | 0.163799 | 0.164205 |

Output checksum (stdout): `199990000`
