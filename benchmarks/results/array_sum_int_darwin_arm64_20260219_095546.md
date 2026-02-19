# array_sum_int benchmark (20260219_095546)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 668a079888e4d234bae4375472d26ba8cf93f9d8
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003804 | 0.003882 | 0.003739 | 0.004154 |
| oren_c | 0.010580 | 0.010632 | 0.010479 | 0.010910 |
| oren_native | 0.019808 | 0.019833 | 0.019611 | 0.020123 |
| oren_obc | 0.607034 | 0.607028 | 0.605764 | 0.608555 |

Output checksum (stdout): `999000000`
