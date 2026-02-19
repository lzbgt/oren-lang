# array_sum benchmark (20260219_130446)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: e6ce345aed3e647a88a133e0f3704171f21e97f2
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004190 | 0.004208 | 0.003993 | 0.004420 |
| oren_c | 0.007941 | 0.008204 | 0.007804 | 0.009091 |
| oren_native | 0.020951 | 0.020869 | 0.020646 | 0.021059 |
| oren_obc | 0.010095 | 0.013583 | 0.009690 | 0.026224 |

Output checksum (stdout): `999000000`
