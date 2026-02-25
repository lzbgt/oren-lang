# multi_list_push_int benchmark (20260225_182552)

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
| c | 0.008680 | 0.008692 | 0.008633 | 0.008800 |
| oren_c | 0.040001 | 0.039792 | 0.039192 | 0.040546 |
| oren_native | 0.028074 | 0.028100 | 0.027724 | 0.028511 |
| oren_obc | 0.524103 | 0.522995 | 0.517450 | 0.525750 |

Output checksum (stdout): `2995000000`
