# dot_product_int benchmark (20260219_020516)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 4fe78cecebca07fef042b244c399a1936c69fdcb
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004940 | 0.004961 | 0.004888 | 0.005090 |
| oren_c | 0.236049 | 0.236247 | 0.233444 | 0.239107 |
| oren_native | 0.358426 | 0.358293 | 0.357206 | 0.359004 |
| oren_obc | 0.897553 | 0.897987 | 0.893974 | 0.900829 |

Output checksum (stdout): `507588000000`
