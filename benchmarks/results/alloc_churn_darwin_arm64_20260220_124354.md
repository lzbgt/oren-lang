# alloc_churn benchmark (20260220_124354)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a3a1cbca71871bbde063b9c64312e3345b3fb82a
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002592 | 0.002604 | 0.002514 | 0.002724 |
| oren_c | 0.029990 | 0.030105 | 0.029858 | 0.030494 |
| oren_native | 3.531648 | 3.532928 | 3.526465 | 3.544326 |
| oren_obc | 0.161888 | 0.161932 | 0.161445 | 0.162594 |

Output checksum (stdout): `199990000`
