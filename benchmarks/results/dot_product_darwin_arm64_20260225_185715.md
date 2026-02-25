# dot_product benchmark (20260225_185715)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 44c0c215a0d1ea12fe55de5ddac1d121ebb9642d
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005840 | 0.005885 | 0.005757 | 0.006068 |
| oren_c | 0.015681 | 0.015428 | 0.014194 | 0.015984 |
| oren_native | 0.024167 | 0.023867 | 0.022971 | 0.024440 |
| oren_obc | 0.397054 | 0.396214 | 0.393696 | 0.398063 |

Output checksum (stdout): `507588000000`
