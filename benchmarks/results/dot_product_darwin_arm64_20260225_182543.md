# dot_product benchmark (20260225_182543)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a5bcb6b0274d4ba760da9b287e6a9d1b89d5872c
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005291 | 0.005445 | 0.005149 | 0.005809 |
| oren_c | 0.013147 | 0.013296 | 0.012993 | 0.013901 |
| oren_native | 0.022359 | 0.022398 | 0.022073 | 0.022955 |
| oren_obc | 0.381411 | 0.381241 | 0.377046 | 0.385106 |

Output checksum (stdout): `507588000000`
