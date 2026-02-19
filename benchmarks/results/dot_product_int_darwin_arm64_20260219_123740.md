# dot_product_int benchmark (20260219_123740)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 6aff4dfa29b756db6ec51040a51c7591553667f2
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005468 | 0.005413 | 0.005274 | 0.005499 |
| oren_c | 0.019166 | 0.019044 | 0.018188 | 0.019642 |
| oren_native | 0.026497 | 0.026623 | 0.026388 | 0.027145 |
| oren_obc | 0.010319 | 0.010325 | 0.009761 | 0.011185 |

Output checksum (stdout): `507588000000`
