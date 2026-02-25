# alloc_churn benchmark (20260225_174653)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 6240cf5215bca1fe71539407cc941eb97bcbcd95
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002785 | 0.002911 | 0.002672 | 0.003312 |
| oren_c | 0.012073 | 0.011980 | 0.011595 | 0.012324 |
| oren_native | 0.018649 | 0.018710 | 0.018434 | 0.019036 |
| oren_obc | 0.162055 | 0.162147 | 0.159999 | 0.164686 |

Output checksum (stdout): `199990000`
