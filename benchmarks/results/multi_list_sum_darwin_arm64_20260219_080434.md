# multi_list_sum benchmark (20260219_080434)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: f12304cf6a19c87209d7ffaef0d005e3d9df0079
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008234 | 0.008321 | 0.008112 | 0.008761 |
| oren_c | 0.182406 | 0.182709 | 0.181473 | 0.184555 |
| oren_native | 0.030427 | 0.030489 | 0.030177 | 0.030718 |
| oren_obc | 1.229163 | 1.229315 | 1.227477 | 1.232098 |

Output checksum (stdout): `2995000000`
