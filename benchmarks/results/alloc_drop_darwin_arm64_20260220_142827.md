# alloc_drop benchmark (20260220_142827)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: dbae7c86d9c6c231b31de03f31815360513ff39c
- runs: 1 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002832 | 0.002832 | 0.002832 | 0.002832 |
| oren_c | 0.004543 | 0.004543 | 0.004543 | 0.004543 |
| oren_native | 3.412235 | 3.412235 | 3.412235 | 3.412235 |
| oren_obc | 0.006844 | 0.006844 | 0.006844 | 0.006844 |

Output checksum (stdout): `alloc_drop keep=11`
