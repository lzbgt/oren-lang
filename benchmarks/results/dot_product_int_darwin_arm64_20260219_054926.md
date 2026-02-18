# dot_product_int benchmark (20260219_054926)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 67e8b53cc823520bcbc2653e379f14fe47ab7c4b
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004745 | 0.004806 | 0.004652 | 0.005105 |
| oren_c | 0.126416 | 0.126499 | 0.126280 | 0.126738 |
| oren_native | 0.024336 | 0.024357 | 0.024240 | 0.024534 |
| oren_obc | 0.892373 | 0.891419 | 0.887804 | 0.894124 |

Output checksum (stdout): `507588000000`
