# dot_product_int benchmark (20260220_072642)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: adb813e9f6902370fd3c103af2d873d6f02782b5
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005494 | 0.005472 | 0.005331 | 0.005608 |
| oren_c | 0.013494 | 0.013316 | 0.012442 | 0.014140 |
| oren_native | 0.022900 | 0.022814 | 0.022358 | 0.023106 |
| oren_obc | 0.009878 | 0.009853 | 0.009632 | 0.010109 |

Output checksum (stdout): `507588000000`
