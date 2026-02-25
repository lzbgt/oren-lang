# alloc_churn benchmark (20260225_175355)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 305af5d016f630892d25dc7393a02281b6c67175
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002789 | 0.002904 | 0.002688 | 0.003172 |
| oren_c | 0.012676 | 0.012765 | 0.012461 | 0.013345 |
| oren_native | 0.019003 | 0.019134 | 0.018680 | 0.020027 |
| oren_obc | 0.161193 | 0.161797 | 0.160214 | 0.165701 |

Output checksum (stdout): `199990000`
