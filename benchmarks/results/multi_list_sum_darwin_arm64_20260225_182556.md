# multi_list_sum benchmark (20260225_182556)

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
| c | 0.008818 | 0.008872 | 0.008543 | 0.009291 |
| oren_c | 0.038444 | 0.038891 | 0.038048 | 0.040696 |
| oren_native | 0.028035 | 0.027917 | 0.027175 | 0.028427 |
| oren_obc | 0.525113 | 0.524828 | 0.520470 | 0.530632 |

Output checksum (stdout): `2995000000`
