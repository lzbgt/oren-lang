# alloc_churn benchmark (20260225_180916)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: b5b14c484ce0df6f7ed4eb76b20242c9fa0e6e22
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002798 | 0.002868 | 0.002765 | 0.003054 |
| oren_c | 0.013054 | 0.013022 | 0.012752 | 0.013154 |
| oren_native | 0.019063 | 0.019180 | 0.018726 | 0.019900 |
| oren_obc | 0.162268 | 0.162569 | 0.160187 | 0.165676 |

Output checksum (stdout): `199990000`
