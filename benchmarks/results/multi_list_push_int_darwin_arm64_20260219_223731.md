# multi_list_push_int benchmark (20260219_223731)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0efd12524e37274075e0cb44e30fe4f484d861ea
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008462 | 0.008503 | 0.008250 | 0.008870 |
| oren_c | 0.038182 | 0.038350 | 0.037580 | 0.039106 |
| oren_native | 0.026836 | 0.026818 | 0.026416 | 0.027333 |
| oren_obc | 0.011507 | 0.011485 | 0.010754 | 0.011936 |

Output checksum (stdout): `2995000000`
