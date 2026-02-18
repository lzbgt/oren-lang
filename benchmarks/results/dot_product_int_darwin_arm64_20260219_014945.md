# dot_product_int benchmark (20260219_014945)

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
| c | 0.006426 | 0.006444 | 0.006173 | 0.006907 |
| oren_c | 0.231913 | 0.231551 | 0.229991 | 0.232801 |
| oren_native | 0.384619 | 0.400279 | 0.376937 | 0.467383 |
| oren_obc | 0.900140 | 0.906892 | 0.897815 | 0.935355 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17334272 | 17334272 | 17334272 | 17334272 |
| oren_c | 97484800 | 97488076 | 97484800 | 97501184 |
| oren_native | 33996800 | 33996800 | 33996800 | 33996800 |
| oren_obc | 135757824 | 135757824 | 135741440 | 135774208 |

Output checksum (stdout): `507588000000`
