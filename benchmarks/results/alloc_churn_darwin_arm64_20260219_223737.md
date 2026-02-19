# alloc_churn benchmark (20260219_223737)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0efd12524e37274075e0cb44e30fe4f484d861ea
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002586 | 0.002586 | 0.002579 | 0.002592 |
| oren_c | 0.036300 | 0.036274 | 0.036007 | 0.036509 |
| oren_native | 0.163014 | 0.163992 | 0.161683 | 0.169455 |
| oren_obc | 0.163026 | 0.163081 | 0.162126 | 0.164013 |

Output checksum (stdout): `199990000`
