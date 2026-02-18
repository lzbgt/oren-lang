# dot_product_int benchmark (20260219_024458)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 5a8f5ba8244a68f5a47bb688a3927ab3c8176fd9
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004755 | 0.004742 | 0.004622 | 0.004867 |
| oren_c | 0.187782 | 0.187718 | 0.187285 | 0.188049 |
| oren_native | 0.283206 | 0.284139 | 0.282057 | 0.287580 |
| oren_obc | 0.900093 | 0.900486 | 0.895086 | 0.905003 |

Output checksum (stdout): `507588000000`
