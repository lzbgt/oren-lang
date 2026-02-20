# alloc_drop benchmark (20260220_143341)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: b2e9c39532bd6c53ace39f7aa3d42bc62d6f9ef5
- runs: 1 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002805 | 0.002805 | 0.002805 | 0.002805 |
| oren_c | 0.004420 | 0.004420 | 0.004420 | 0.004420 |
| oren_native | 0.177912 | 0.177912 | 0.177912 | 0.177912 |
| oren_obc | 0.006617 | 0.006617 | 0.006617 | 0.006617 |

Output checksum (stdout): `alloc_drop keep=11`
