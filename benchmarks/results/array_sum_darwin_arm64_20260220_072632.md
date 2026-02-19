# array_sum benchmark (20260220_072632)

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
| c | 0.004369 | 0.004465 | 0.004016 | 0.005329 |
| oren_c | 0.031628 | 0.031638 | 0.030667 | 0.032180 |
| oren_native | 0.028946 | 0.029229 | 0.028597 | 0.030098 |
| oren_obc | 0.148625 | 0.148571 | 0.147943 | 0.149202 |

Output checksum (stdout): `999000000`
