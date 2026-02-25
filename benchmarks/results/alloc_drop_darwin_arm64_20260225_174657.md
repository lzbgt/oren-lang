# alloc_drop benchmark (20260225_174657)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 6240cf5215bca1fe71539407cc941eb97bcbcd95
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002954 | 0.002974 | 0.002721 | 0.003329 |
| oren_c | 0.004877 | 0.004846 | 0.004484 | 0.005207 |
| oren_native | 0.158792 | 0.158691 | 0.155571 | 0.161981 |
| oren_obc | 0.007393 | 0.007296 | 0.006826 | 0.007701 |

Output checksum (stdout): `alloc_drop keep=11`
