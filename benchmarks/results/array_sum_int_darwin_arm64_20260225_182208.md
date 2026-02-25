# array_sum_int benchmark (20260225_182208)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1e81dc28a1d4d88d1e1ddc63949a1f6780bedd28
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004395 | 0.004411 | 0.003983 | 0.004728 |
| oren_c | 0.008997 | 0.009108 | 0.008854 | 0.009389 |
| oren_native | 0.016386 | 0.016434 | 0.016195 | 0.016858 |
| oren_obc | 0.255468 | 0.255349 | 0.253040 | 0.258038 |

Output checksum (stdout): `999000000`
