# array_sum_int benchmark (20260219_144341)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: e822da441885170ae3986c7de2a80fcca7a73e47
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004914 | 0.005598 | 0.004725 | 0.007801 |
| oren_c | 0.010160 | 0.010053 | 0.009539 | 0.010427 |
| oren_native | 0.022312 | 0.022317 | 0.021479 | 0.022909 |
| oren_obc | 0.005768 | 0.005720 | 0.005525 | 0.005891 |

Output checksum (stdout): `999000000`
