# array_sum_int benchmark (20260219_061129)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 3ed81f21c2d6c09e73df0966da00f810f72bd503
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003776 | 0.003840 | 0.003707 | 0.004083 |
| oren_c | 0.039230 | 0.039067 | 0.038526 | 0.039357 |
| oren_native | 0.020048 | 0.020095 | 0.019989 | 0.020259 |
| oren_obc | 0.621182 | 0.621458 | 0.620199 | 0.622541 |

Output checksum (stdout): `999000000`
