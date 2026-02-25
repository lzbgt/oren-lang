# array_sum benchmark (20260225_182203)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1e81dc28a1d4d88d1e1ddc63949a1f6780bedd28
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004806 | 0.004786 | 0.004632 | 0.004928 |
| oren_c | 0.009595 | 0.009574 | 0.008979 | 0.010237 |
| oren_native | 0.017047 | 0.017077 | 0.016841 | 0.017346 |
| oren_obc | 0.267635 | 0.266909 | 0.262999 | 0.268683 |

Output checksum (stdout): `999000000`
