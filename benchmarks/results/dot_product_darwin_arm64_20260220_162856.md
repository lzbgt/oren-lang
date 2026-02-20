# dot_product benchmark (20260220_162856)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: eb664191806e0b3565f2f21b20891a8e22aaa9f8
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005011 | 0.005098 | 0.004879 | 0.005619 |
| oren_c | 0.012893 | 0.013152 | 0.012831 | 0.013652 |
| oren_native | 0.020850 | 0.020992 | 0.020345 | 0.021571 |
| oren_obc | 0.376919 | 0.378298 | 0.376003 | 0.383263 |

Output checksum (stdout): `507588000000`
