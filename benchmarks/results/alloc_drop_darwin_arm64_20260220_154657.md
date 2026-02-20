# alloc_drop benchmark (20260220_154657)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 261ccbd932ead1966530978f5ff71a2e56181510
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002856 | 0.002907 | 0.002756 | 0.003227 |
| oren_c | 0.004390 | 0.004446 | 0.004371 | 0.004547 |
| oren_native | 0.160444 | 0.160488 | 0.159976 | 0.161055 |
| oren_obc | 0.006616 | 0.006688 | 0.006554 | 0.006962 |

Output checksum (stdout): `alloc_drop keep=11`
