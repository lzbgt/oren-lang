# dot_product benchmark (20260219_093227)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 78c4364259315a94e197c814062078bac83f8f5a
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004806 | 0.004863 | 0.004609 | 0.005312 |
| oren_c | 0.017406 | 0.017285 | 0.016934 | 0.017433 |
| oren_native | 0.024430 | 0.024443 | 0.024195 | 0.024720 |
| oren_obc | 0.574974 | 0.575024 | 0.573465 | 0.576943 |

Output checksum (stdout): `507588000000`
