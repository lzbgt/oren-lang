# dot_product_int benchmark (20260219_054554)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 7677b05c1ab0d185abb3494fbd3aab6e31defe37
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004886 | 0.004993 | 0.004757 | 0.005250 |
| oren_c | 0.154683 | 0.154676 | 0.154323 | 0.155082 |
| oren_native | 0.024859 | 0.025102 | 0.024734 | 0.025806 |
| oren_obc | 0.890823 | 0.890984 | 0.888472 | 0.894559 |

Output checksum (stdout): `507588000000`
