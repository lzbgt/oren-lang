# multi_list_push_int benchmark (20260225_182227)

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
| c | 0.009445 | 0.009806 | 0.009375 | 0.010680 |
| oren_c | 0.040652 | 0.041049 | 0.039255 | 0.043491 |
| oren_native | 0.028458 | 0.028611 | 0.028164 | 0.029082 |
| oren_obc | 0.521388 | 0.522016 | 0.517546 | 0.526470 |

Output checksum (stdout): `2995000000`
