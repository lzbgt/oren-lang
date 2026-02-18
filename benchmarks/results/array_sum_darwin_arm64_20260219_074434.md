# array_sum benchmark (20260219_074434)

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
| c | 0.003651 | 0.003828 | 0.003634 | 0.004411 |
| oren_c | 0.115232 | 0.115717 | 0.114689 | 0.117905 |
| oren_native | 0.019640 | 0.019747 | 0.019508 | 0.020033 |
| oren_obc | 0.623438 | 0.623089 | 0.620535 | 0.624639 |

Output checksum (stdout): `999000000`
