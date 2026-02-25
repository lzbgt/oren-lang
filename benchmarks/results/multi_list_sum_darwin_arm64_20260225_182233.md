# multi_list_sum benchmark (20260225_182233)

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
| c | 0.009473 | 0.009707 | 0.009364 | 0.010458 |
| oren_c | 0.044986 | 0.044640 | 0.042686 | 0.046193 |
| oren_native | 0.030610 | 0.030464 | 0.029698 | 0.031251 |
| oren_obc | 0.526488 | 0.525011 | 0.521017 | 0.527930 |

Output checksum (stdout): `2995000000`
