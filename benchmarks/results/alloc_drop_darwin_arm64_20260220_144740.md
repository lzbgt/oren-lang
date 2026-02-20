# alloc_drop benchmark (20260220_144740)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 78c7cda66fc818687dc4444d9bd985a874739a18
- runs: 1 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003239 | 0.003239 | 0.003239 | 0.003239 |
| oren_c | 0.004935 | 0.004935 | 0.004935 | 0.004935 |
| oren_native | 19.055775 | 19.055775 | 19.055775 | 19.055775 |
| oren_obc | 0.007315 | 0.007315 | 0.007315 | 0.007315 |

Output checksum (stdout): `alloc_drop keep=11`
