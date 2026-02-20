# alloc_drop benchmark (20260220_143057)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: ae4e3d5d91371f11d1454297dcc3f0a09f272dc9
- runs: 1 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002958 | 0.002958 | 0.002958 | 0.002958 |
| oren_c | 0.004484 | 0.004484 | 0.004484 | 0.004484 |
| oren_native | 3.215916 | 3.215916 | 3.215916 | 3.215916 |
| oren_obc | 0.006913 | 0.006913 | 0.006913 | 0.006913 |

Output checksum (stdout): `alloc_drop keep=11`
