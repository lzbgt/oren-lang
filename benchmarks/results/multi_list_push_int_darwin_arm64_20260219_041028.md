# multi_list_push_int benchmark (20260219_041028)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 46c1dfe7181ea6b89e3a67b251989ea669b26b64
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.007738 | 0.007834 | 0.007709 | 0.008157 |
| oren_c | 0.162289 | 0.162365 | 0.160751 | 0.163841 |
| oren_native | 0.440384 | 0.440343 | 0.438876 | 0.441881 |
| oren_obc | 1.230430 | 1.230101 | 1.226109 | 1.233285 |

Output checksum (stdout): `2995000000`
