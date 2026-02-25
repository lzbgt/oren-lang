# multi_list_push_int benchmark (20260225_185730)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 44c0c215a0d1ea12fe55de5ddac1d121ebb9642d
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.010196 | 0.010303 | 0.009989 | 0.010952 |
| oren_c | 0.044209 | 0.044519 | 0.043533 | 0.045762 |
| oren_native | 0.030857 | 0.030905 | 0.030564 | 0.031425 |
| oren_obc | 0.546791 | 0.546996 | 0.545313 | 0.549182 |

Output checksum (stdout): `2995000000`
