# dot_product benchmark (20260219_090209)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: e9f99b2f9f9e7d4c2aff8666eeaa24757420835a
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004775 | 0.004787 | 0.004770 | 0.004831 |
| oren_c | 0.017432 | 0.017605 | 0.016962 | 0.018472 |
| oren_native | 0.025363 | 0.025469 | 0.025259 | 0.025941 |
| oren_obc | 0.894463 | 0.894179 | 0.891937 | 0.896237 |

Output checksum (stdout): `507588000000`
