# dot_product_int benchmark (20260219_064258)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a8e448776d4a082a094b95f1f38e04e7a04eabfc
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004823 | 0.004804 | 0.004678 | 0.004964 |
| oren_c | 0.017694 | 0.017580 | 0.017225 | 0.017873 |
| oren_native | 0.025182 | 0.025360 | 0.024928 | 0.025933 |
| oren_obc | 0.892456 | 0.893295 | 0.890738 | 0.898150 |

Output checksum (stdout): `507588000000`
