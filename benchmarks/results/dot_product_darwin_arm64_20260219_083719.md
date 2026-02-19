# dot_product benchmark (20260219_083719)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 93a175eaf28cde729f91381e248dfc9685c68ef6
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004755 | 0.004748 | 0.004663 | 0.004841 |
| oren_c | 0.017197 | 0.017174 | 0.016996 | 0.017382 |
| oren_native | 0.134998 | 0.135375 | 0.134324 | 0.137469 |
| oren_obc | 0.892852 | 0.893463 | 0.891569 | 0.895870 |

Output checksum (stdout): `507588000000`
