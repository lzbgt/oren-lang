# dot_product benchmark (20260219_212500)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: cae755bb4dc08b4389e0a7432bab1e27c256bf96
- runs: 3 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005483 | 0.005469 | 0.005350 | 0.005574 |
| oren_c | 0.013845 | 0.013729 | 0.013482 | 0.013860 |
| oren_native | 0.025854 | 0.025866 | 0.025797 | 0.025948 |
| oren_obc | 0.012491 | 0.012705 | 0.012368 | 0.013256 |

Output checksum (stdout): `507588000000`
