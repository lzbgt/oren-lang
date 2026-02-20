# alloc_drop benchmark (20260220_130348)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 2958d2f561eb672a0cf85bf358dc5b428a030d9e
- runs: 5 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002832 | 0.002885 | 0.002773 | 0.003162 |
| oren_c | 0.004410 | 0.004565 | 0.004306 | 0.005259 |
| oren_native | 0.155754 | 0.155529 | 0.153638 | 0.157041 |
| oren_obc | 0.006588 | 0.006662 | 0.006520 | 0.006933 |

## Alloc sites (median counts)

| variant | total | list_header | list_int_header | list_buf | list_int_buf |
| --- | --- | --- | --- | --- | --- |
| oren_native | 10042 | 10011 | 0 | 31 | 0 |

Output checksum (stdout): `alloc_drop keep=11
alloc_drop keep=11
alloc_drop keep=11
alloc_drop keep=11
alloc_drop keep=11`
