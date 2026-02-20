# array_sum benchmark (20260220_162853)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: eb664191806e0b3565f2f21b20891a8e22aaa9f8
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003928 | 0.003988 | 0.003732 | 0.004280 |
| oren_c | 0.008314 | 0.008296 | 0.007784 | 0.008768 |
| oren_native | 0.015737 | 0.015901 | 0.015497 | 0.016546 |
| oren_obc | 0.144631 | 0.144268 | 0.143104 | 0.144968 |

Output checksum (stdout): `999000000`
