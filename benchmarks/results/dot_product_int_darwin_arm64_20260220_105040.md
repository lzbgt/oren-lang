# dot_product_int benchmark (20260220_105040)

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
| c | 0.004929 | 0.004945 | 0.004918 | 0.004998 |
| oren_c | 0.013228 | 0.013273 | 0.012920 | 0.013696 |
| oren_native | 0.021600 | 0.021722 | 0.021518 | 0.022091 |
| oren_obc | 0.009287 | 0.009246 | 0.009154 | 0.009293 |

Output checksum (stdout): `507588000000`
