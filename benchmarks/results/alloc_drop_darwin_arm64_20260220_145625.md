# alloc_drop benchmark (20260220_145625)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 64958ab5dac08f306f7059d1b986c6a0c33db19f
- runs: 1 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002906 | 0.002906 | 0.002906 | 0.002906 |
| oren_c | 0.004438 | 0.004438 | 0.004438 | 0.004438 |
| oren_native | 3.189248 | 3.189248 | 3.189248 | 3.189248 |
| oren_obc | 0.006722 | 0.006722 | 0.006722 | 0.006722 |

Output checksum (stdout): `alloc_drop keep=11`
