# dot_product_int benchmark (20260219_011820)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 490aad5f257ff9475f08bb250f62a44584fe795d
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.006687 | 0.006717 | 0.006478 | 0.007070 |
| oren_c | 0.228439 | 0.228572 | 0.228104 | 0.229428 |
| oren_native | 0.363570 | 0.363382 | 0.362629 | 0.363986 |
| oren_obc | 0.908891 | 0.908690 | 0.906045 | 0.910903 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17334272 | 17330995 | 17317888 | 17334272 |
| oren_c | 97501184 | 97501184 | 97501184 | 97501184 |
| oren_native | 33996800 | 33996800 | 33996800 | 33996800 |
| oren_obc | 135757824 | 135754547 | 135741440 | 135757824 |

Output checksum (stdout): `507588000000`
