# array_sum benchmark (20260220_042051)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: f2fcc8abe0025a6cc88b3f20199669e9794e736c
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004218 | 0.004223 | 0.004085 | 0.004397 |
| oren_c | 0.008191 | 0.008229 | 0.007969 | 0.008467 |
| oren_native | 0.016020 | 0.015970 | 0.015857 | 0.016053 |
| oren_obc | 0.009304 | 0.009338 | 0.008638 | 0.009928 |

Output checksum (stdout): `999000000`
