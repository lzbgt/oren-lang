# multi_list_sum benchmark (20260220_072651)

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
| c | 0.008901 | 0.008903 | 0.008651 | 0.009144 |
| oren_c | 0.070321 | 0.070266 | 0.069824 | 0.070515 |
| oren_native | 0.072441 | 0.072264 | 0.071390 | 0.072831 |
| oren_obc | 0.322278 | 0.322352 | 0.320872 | 0.323987 |

Output checksum (stdout): `2995000000`
