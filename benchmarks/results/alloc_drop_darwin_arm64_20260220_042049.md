# alloc_drop benchmark (20260220_042049)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: f2fcc8abe0025a6cc88b3f20199669e9794e736c
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002843 | 0.002871 | 0.002743 | 0.003056 |
| oren_c | 0.004388 | 0.004393 | 0.004297 | 0.004493 |
| oren_native | 0.097563 | 0.097993 | 0.095779 | 0.100098 |
| oren_obc | 0.007365 | 0.007334 | 0.007138 | 0.007456 |

Output checksum (stdout): `alloc_drop keep=11`
