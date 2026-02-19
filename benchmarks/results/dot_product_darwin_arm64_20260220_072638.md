# dot_product benchmark (20260220_072638)

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
| c | 0.005621 | 0.005628 | 0.005345 | 0.005858 |
| oren_c | 0.050342 | 0.050643 | 0.050271 | 0.051301 |
| oren_native | 0.056961 | 0.057076 | 0.056634 | 0.057859 |
| oren_obc | 0.252915 | 0.253291 | 0.252626 | 0.254861 |

Output checksum (stdout): `507588000000`
