# alloc_drop benchmark (20260219_223741)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0efd12524e37274075e0cb44e30fe4f484d861ea
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002722 | 0.002701 | 0.002605 | 0.002774 |
| oren_c | 0.004360 | 0.004378 | 0.004323 | 0.004444 |
| oren_native | 0.102530 | 0.102254 | 0.099629 | 0.105171 |
| oren_obc | 0.006801 | 0.006829 | 0.006612 | 0.007241 |

Output checksum (stdout): `alloc_drop keep=11`
