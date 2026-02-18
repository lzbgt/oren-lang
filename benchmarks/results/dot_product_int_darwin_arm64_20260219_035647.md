# dot_product_int benchmark (20260219_035647)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1f2f09f441d087161562e03f9e9fab1f6d9cbd92
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004784 | 0.004885 | 0.004698 | 0.005356 |
| oren_c | 0.072135 | 0.072243 | 0.071970 | 0.072752 |
| oren_native | 0.065333 | 0.065395 | 0.065146 | 0.065832 |
| oren_obc | 0.898854 | 0.898845 | 0.898068 | 0.899612 |

Output checksum (stdout): `507588000000`
