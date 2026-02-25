# alloc_churn benchmark (20260225_182158)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1e81dc28a1d4d88d1e1ddc63949a1f6780bedd28
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003049 | 0.003009 | 0.002632 | 0.003310 |
| oren_c | 0.012431 | 0.012394 | 0.011973 | 0.012911 |
| oren_native | 0.018969 | 0.018945 | 0.018662 | 0.019187 |
| oren_obc | 0.164831 | 0.164355 | 0.161975 | 0.166649 |

Output checksum (stdout): `199990000`
