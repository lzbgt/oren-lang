# multi_list_push_int benchmark (20260219_122050)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 164142d78b77a8a39525a1cc0c9b608439cd7cc8
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.009375 | 0.009468 | 0.009058 | 0.010128 |
| oren_c | 0.083655 | 0.085761 | 0.081519 | 0.096403 |
| oren_native | 0.034152 | 0.033872 | 0.032905 | 0.034520 |
| oren_obc | 0.761596 | 0.758340 | 0.738100 | 0.767390 |

Output checksum (stdout): `2995000000`
