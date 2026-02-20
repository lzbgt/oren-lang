# array_sum benchmark (20260220_161439)

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
| c | 0.004009 | 0.004042 | 0.003925 | 0.004286 |
| oren_c | 0.007599 | 0.007556 | 0.007374 | 0.007708 |
| oren_native | 0.016099 | 0.015951 | 0.015430 | 0.016306 |
| oren_obc | 0.142656 | 0.142604 | 0.141966 | 0.143101 |

Output checksum (stdout): `999000000`
