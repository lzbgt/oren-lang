# dot_product_int benchmark (20260219_122046)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 164142d78b77a8a39525a1cc0c9b608439cd7cc8
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005722 | 0.005717 | 0.005415 | 0.006137 |
| oren_c | 0.018668 | 0.018540 | 0.018085 | 0.019096 |
| oren_native | 0.025657 | 0.025441 | 0.024881 | 0.025683 |
| oren_obc | 0.549362 | 0.549401 | 0.545886 | 0.553736 |

Output checksum (stdout): `507588000000`
