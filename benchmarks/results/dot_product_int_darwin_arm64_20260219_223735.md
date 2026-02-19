# dot_product_int benchmark (20260219_223735)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0efd12524e37274075e0cb44e30fe4f484d861ea
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004893 | 0.004868 | 0.004770 | 0.004949 |
| oren_c | 0.013196 | 0.013290 | 0.012741 | 0.013836 |
| oren_native | 0.021647 | 0.021616 | 0.020914 | 0.022330 |
| oren_obc | 0.009513 | 0.009533 | 0.009365 | 0.009783 |

Output checksum (stdout): `507588000000`
