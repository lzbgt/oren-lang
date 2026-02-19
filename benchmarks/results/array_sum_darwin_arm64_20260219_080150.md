# array_sum benchmark (20260219_080150)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 4f844df0ab06d07868ec445442bfb30f04588080
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003835 | 0.003974 | 0.003745 | 0.004396 |
| oren_c | 0.073876 | 0.073791 | 0.073438 | 0.074091 |
| oren_native | 0.019664 | 0.019668 | 0.019574 | 0.019767 |
| oren_obc | 0.623274 | 0.624546 | 0.621253 | 0.630742 |

Output checksum (stdout): `999000000`
