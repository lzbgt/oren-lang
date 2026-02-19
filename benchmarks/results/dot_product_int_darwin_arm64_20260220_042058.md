# dot_product_int benchmark (20260220_042058)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: f2fcc8abe0025a6cc88b3f20199669e9794e736c
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005082 | 0.005075 | 0.005038 | 0.005106 |
| oren_c | 0.012445 | 0.012412 | 0.012144 | 0.012801 |
| oren_native | 0.022297 | 0.022523 | 0.022049 | 0.023180 |
| oren_obc | 0.009167 | 0.009227 | 0.009130 | 0.009444 |

Output checksum (stdout): `507588000000`
