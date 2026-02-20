# dot_product benchmark (20260220_161442)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: eb68efa24b86bbb37dc2f3c7c5bac65b3bf9e8af
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004951 | 0.004946 | 0.004894 | 0.005009 |
| oren_c | 0.012387 | 0.012439 | 0.012065 | 0.013044 |
| oren_native | 0.020451 | 0.020470 | 0.020247 | 0.020848 |
| oren_obc | 0.378178 | 0.378081 | 0.376640 | 0.379867 |

Output checksum (stdout): `507588000000`
