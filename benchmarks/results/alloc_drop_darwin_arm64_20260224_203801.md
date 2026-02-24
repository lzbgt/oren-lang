# alloc_drop benchmark (20260224_203801)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 20bc02b36b682e0711daf4f0cf8b753e138ef415
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003118 | 0.003084 | 0.002996 | 0.003137 |
| oren_c | 0.004599 | 0.004696 | 0.004492 | 0.005012 |
| oren_native | 0.194828 | 0.194402 | 0.192232 | 0.195808 |
| oren_obc | 0.007305 | 0.007251 | 0.007032 | 0.007419 |

Output checksum (stdout): `alloc_drop keep=11`
