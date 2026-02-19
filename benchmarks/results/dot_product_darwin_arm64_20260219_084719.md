# dot_product benchmark (20260219_084719)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: e8d1736bb2665b60d9ee260e618b2787b2eabee7
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004889 | 0.004876 | 0.004757 | 0.005039 |
| oren_c | 0.017255 | 0.017312 | 0.017156 | 0.017618 |
| oren_native | 0.025528 | 0.025608 | 0.025360 | 0.025938 |
| oren_obc | 0.893932 | 0.893660 | 0.891810 | 0.894845 |

Output checksum (stdout): `507588000000`
