# dot_product_int benchmark (20260219_011037)

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
| c | 0.006597 | 0.006658 | 0.006456 | 0.007030 |
| oren_c | 0.326462 | 0.325906 | 0.324307 | 0.326715 |
| oren_native | 0.359219 | 0.360413 | 0.358126 | 0.364168 |
| oren_obc | 0.893448 | 0.894091 | 0.890649 | 0.899762 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17334272 | 17337548 | 17334272 | 17350656 |
| oren_c | 97763328 | 97763328 | 97763328 | 97763328 |
| oren_native | 33996800 | 33996800 | 33996800 | 33996800 |
| oren_obc | 135757824 | 135757824 | 135757824 | 135757824 |

Output checksum (stdout): `507588000000`
