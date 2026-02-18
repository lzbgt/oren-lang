# dot_product_int benchmark (20260219_011245)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: c0027910c6a0c7ed204d876cfefd89b2485ccda1
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.007073 | 0.007022 | 0.006549 | 0.007286 |
| oren_c | 0.332234 | 0.332629 | 0.331661 | 0.333674 |
| oren_native | 0.364811 | 0.365991 | 0.363320 | 0.371519 |
| oren_obc | 0.910610 | 0.911548 | 0.909996 | 0.916085 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17334272 | 17334272 | 17334272 | 17334272 |
| oren_c | 97763328 | 97763328 | 97746944 | 97779712 |
| oren_native | 33996800 | 33996800 | 33996800 | 33996800 |
| oren_obc | 135757824 | 135747993 | 135725056 | 135757824 |

Output checksum (stdout): `507588000000`
