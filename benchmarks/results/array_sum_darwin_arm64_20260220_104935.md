# array_sum benchmark (20260220_104935)

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
| c | 0.004031 | 0.004051 | 0.003811 | 0.004419 |
| oren_c | 0.030207 | 0.030140 | 0.029938 | 0.030316 |
| oren_native | 3.114184 | 3.116077 | 3.111363 | 3.122988 |
| oren_obc | 0.143692 | 0.143628 | 0.142804 | 0.144903 |

Output checksum (stdout): `999000000`
