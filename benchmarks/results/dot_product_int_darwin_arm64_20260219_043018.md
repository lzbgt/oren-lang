# dot_product_int benchmark (20260219_043018)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: ae19b5ca23cb5a8a7098b3a3235b17fb6b6c6334
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004702 | 0.004729 | 0.004597 | 0.004874 |
| oren_c | 0.071653 | 0.071670 | 0.071272 | 0.072223 |
| oren_native | 0.024691 | 0.024710 | 0.024441 | 0.025029 |
| oren_obc | 0.897349 | 0.896970 | 0.895240 | 0.897983 |

Output checksum (stdout): `507588000000`
