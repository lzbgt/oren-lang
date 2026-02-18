# dot_product_int benchmark (20260218_224421)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1557bd3e023e8007d19e94932be6bb4a656b4c88
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004928 | 0.004957 | 0.004861 | 0.005094 |
| oren_c | 0.333877 | 0.334201 | 0.333326 | 0.335325 |
| oren_native | 0.516714 | 0.522223 | 0.515535 | 0.534771 |
| oren_obc | 0.932976 | 0.951957 | 0.927879 | 0.983762 |

Output checksum (stdout): `507588000000`
