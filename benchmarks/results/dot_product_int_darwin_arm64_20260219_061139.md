# dot_product_int benchmark (20260219_061139)

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
| c | 0.004787 | 0.005065 | 0.004759 | 0.005771 |
| oren_c | 0.072347 | 0.072381 | 0.071420 | 0.073469 |
| oren_native | 0.024660 | 0.024603 | 0.024394 | 0.024788 |
| oren_obc | 0.889126 | 0.890060 | 0.888398 | 0.892743 |

Output checksum (stdout): `507588000000`
