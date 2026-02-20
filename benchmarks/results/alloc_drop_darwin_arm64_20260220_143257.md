# alloc_drop benchmark (20260220_143257)

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
| c | 0.002755 | 0.002755 | 0.002755 | 0.002755 |
| oren_c | 0.004403 | 0.004403 | 0.004403 | 0.004403 |
| oren_native | 3.206942 | 3.206942 | 3.206942 | 3.206942 |
| oren_obc | 0.006863 | 0.006863 | 0.006863 | 0.006863 |

Output checksum (stdout): `alloc_drop keep=11`
