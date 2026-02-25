# multi_list_push_int benchmark (20260225_180945)

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
| c | 0.009892 | 0.009654 | 0.009000 | 0.010104 |
| oren_c | 0.041094 | 0.040978 | 0.040320 | 0.041568 |
| oren_native | 0.029105 | 0.029133 | 0.028150 | 0.030574 |
| oren_obc | 0.525091 | 0.524888 | 0.518748 | 0.527906 |

Output checksum (stdout): `2995000000`
