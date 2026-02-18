# array_sum benchmark (20260219_072645)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 82ec42e3fc2b066dcba190d2a14a3d325b9c187b
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003711 | 0.003758 | 0.003626 | 0.003956 |
| oren_c | 0.114567 | 0.114472 | 0.114037 | 0.114862 |
| oren_native | 0.141036 | 0.141463 | 0.140758 | 0.142774 |
| oren_obc | 0.620653 | 0.621001 | 0.619686 | 0.622175 |

Output checksum (stdout): `999000000`
