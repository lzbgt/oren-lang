# dot_product benchmark (20260220_104959)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: ea30b50a2c9482a01f8485e45c0bc42944757135
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004948 | 0.004929 | 0.004840 | 0.005027 |
| oren_c | 0.048653 | 0.048790 | 0.048577 | 0.049142 |
| oren_native | 6.228725 | 6.225198 | 6.211860 | 6.232136 |
| oren_obc | 0.244564 | 0.243922 | 0.238883 | 0.248553 |

Output checksum (stdout): `507588000000`
