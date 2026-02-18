# array_sum benchmark (20260219_075538)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 9207c67aad11c6577f4a9f72940a57e41173944e
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003897 | 0.003938 | 0.003704 | 0.004309 |
| oren_c | 0.072994 | 0.073075 | 0.072725 | 0.073439 |
| oren_native | 0.019627 | 0.019732 | 0.019561 | 0.020121 |
| oren_obc | 0.621733 | 0.622076 | 0.620064 | 0.624831 |

Output checksum (stdout): `999000000`
