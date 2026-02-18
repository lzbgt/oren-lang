# array_sum_int benchmark (20260218_230227)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 3c43d9fa5b0caf158aab2dd2261126ce95847a72
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004330 | 0.004303 | 0.004234 | 0.004342 |
| oren_c | 0.206940 | 0.208831 | 0.206138 | 0.212461 |
| oren_native | 0.225811 | 0.225841 | 0.222824 | 0.229968 |
| oren_obc | 0.656232 | 0.656532 | 0.648658 | 0.662779 |

Output checksum (stdout): `999000000`
