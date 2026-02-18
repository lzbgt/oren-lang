# dot_product_int benchmark (20260219_021503)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: dae2f5d2bf2a40b1344d3eaa80ed1617992553fd
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005123 | 0.005220 | 0.004936 | 0.005825 |
| oren_c | 0.204359 | 0.204202 | 0.203512 | 0.204745 |
| oren_native | 0.359883 | 0.360771 | 0.358705 | 0.364660 |
| oren_obc | 0.901200 | 0.901018 | 0.897227 | 0.906354 |

Output checksum (stdout): `507588000000`
