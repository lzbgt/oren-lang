# alloc_drop benchmark (20260220_143539)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 729eab59ac29e780ac4b413c070121a4bca5dbd4
- runs: 1 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002796 | 0.002796 | 0.002796 | 0.002796 |
| oren_c | 0.004454 | 0.004454 | 0.004454 | 0.004454 |
| oren_native | 3.399042 | 3.399042 | 3.399042 | 3.399042 |
| oren_obc | 0.006925 | 0.006925 | 0.006925 | 0.006925 |

Output checksum (stdout): `alloc_drop keep=11`
