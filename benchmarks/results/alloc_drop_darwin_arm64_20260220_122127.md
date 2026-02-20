# alloc_drop benchmark (20260220_122127)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 71a8acbb54c6cf7cd8f5c8971b12c80725f1e3db
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002735 | 0.002806 | 0.002660 | 0.003189 |
| oren_c | 0.004371 | 0.004365 | 0.004256 | 0.004457 |
| oren_native | 0.151924 | 0.152019 | 0.151059 | 0.153321 |
| oren_obc | 0.006584 | 0.006599 | 0.006531 | 0.006669 |

Output checksum (stdout): `alloc_drop keep=11`
