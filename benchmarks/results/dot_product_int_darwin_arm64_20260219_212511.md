# dot_product_int benchmark (20260219_212511)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: cae755bb4dc08b4389e0a7432bab1e27c256bf96
- runs: 3 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005038 | 0.005088 | 0.004995 | 0.005229 |
| oren_c | 0.013702 | 0.013829 | 0.013635 | 0.014151 |
| oren_native | 0.025899 | 0.025864 | 0.025742 | 0.025951 |
| oren_obc | 0.009075 | 0.009094 | 0.008960 | 0.009248 |

Output checksum (stdout): `507588000000`
