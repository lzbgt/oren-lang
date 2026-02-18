# dot_product_int benchmark (20260219_060427)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 05654972c13598333b733ef850c452b2c9b27d14
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004800 | 0.004796 | 0.004655 | 0.005004 |
| oren_c | 0.113551 | 0.113739 | 0.113083 | 0.114651 |
| oren_native | 0.024767 | 0.024832 | 0.024545 | 0.025389 |
| oren_obc | 0.888789 | 0.889105 | 0.887588 | 0.890589 |

Output checksum (stdout): `507588000000`
