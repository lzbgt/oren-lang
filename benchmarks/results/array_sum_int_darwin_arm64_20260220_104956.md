# array_sum_int benchmark (20260220_104956)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: ea30b50a2c9482a01f8485e45c0bc42944757135
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003865 | 0.004168 | 0.003790 | 0.005196 |
| oren_c | 0.007937 | 0.007966 | 0.007730 | 0.008357 |
| oren_native | 0.015926 | 0.016103 | 0.015902 | 0.016536 |
| oren_obc | 0.004629 | 0.004649 | 0.004577 | 0.004749 |

Output checksum (stdout): `999000000`
