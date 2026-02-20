# alloc_churn benchmark (20260220_123817)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: b21bb0cfbf2d0672879a4778a54d10d0740aff66
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002621 | 0.002645 | 0.002571 | 0.002793 |
| oren_c | 0.029978 | 0.029921 | 0.029753 | 0.030017 |
| oren_native | 0.323806 | 0.324832 | 0.322472 | 0.329162 |
| oren_obc | 0.161957 | 0.162104 | 0.161451 | 0.163002 |

Output checksum (stdout): `199990000`
