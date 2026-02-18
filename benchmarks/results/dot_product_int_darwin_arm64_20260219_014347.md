# dot_product_int benchmark (20260219_014347)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 583c45635bcc7baacf4a3bdc1cfe8d977ef27f62
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.006387 | 0.006478 | 0.006210 | 0.006990 |
| oren_c | 0.358458 | 0.358610 | 0.357483 | 0.359924 |
| oren_native | 0.362972 | 0.362250 | 0.358417 | 0.364418 |
| oren_obc | 0.902229 | 0.902003 | 0.898846 | 0.904093 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17334272 | 17334272 | 17334272 | 17334272 |
| oren_c | 97746944 | 97746944 | 97730560 | 97763328 |
| oren_native | 33996800 | 33996800 | 33996800 | 33996800 |
| oren_obc | 135757824 | 135754547 | 135741440 | 135757824 |

Output checksum (stdout): `507588000000`
