# alloc_drop benchmark (20260220_115652)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: f706f7583077433ded805081c9e522407eb14a57
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003016 | 0.003016 | 0.003016 | 0.003016 |
| oren_c | 0.005051 | 0.005051 | 0.005051 | 0.005051 |
| oren_native | 0.158219 | 0.158219 | 0.158219 | 0.158219 |
| oren_obc | 0.008531 | 0.008531 | 0.008531 | 0.008531 |

Output checksum (stdout): `alloc_drop keep=11`
