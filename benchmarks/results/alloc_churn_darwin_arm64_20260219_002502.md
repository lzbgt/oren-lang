# alloc_churn benchmark (20260219_002502)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0019373d6f61ff78e0bfdc6530183f2c9bf44c37
- runs: 3 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004179 | 0.004272 | 0.004128 | 0.004509 |
| oren_c | 0.115068 | 0.114731 | 0.113527 | 0.115597 |
| oren_native | 0.694654 | 0.693504 | 0.688967 | 0.696892 |
| oren_obc | 0.407483 | 0.408883 | 0.407151 | 0.412016 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 1294336 | 1294336 | 1294336 | 1294336 |
| oren_c | 68665344 | 68670805 | 68665344 | 68681728 |
| oren_native | 53805056 | 53805056 | 53805056 | 53805056 |
| oren_obc | 61390848 | 61379925 | 61358080 | 61390848 |

Output checksum (stdout): `199990000`
