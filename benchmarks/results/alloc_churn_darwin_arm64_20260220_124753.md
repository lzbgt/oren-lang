# alloc_churn benchmark (20260220_124753)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: e0762ee74bc28673e3628c6da05113eeef2644d5
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002616 | 0.002618 | 0.002552 | 0.002703 |
| oren_c | 0.030231 | 0.030190 | 0.030005 | 0.030302 |
| oren_native | 3.406192 | 3.407466 | 3.402541 | 3.417038 |
| oren_obc | 0.163301 | 0.163484 | 0.162439 | 0.165541 |

Output checksum (stdout): `199990000`
