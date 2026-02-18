# dot_product_int benchmark (20260219_013026)

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
| c | 0.006710 | 0.006729 | 0.006470 | 0.006997 |
| oren_c | 0.231391 | 0.231588 | 0.230642 | 0.233016 |
| oren_native | 0.365394 | 0.366064 | 0.364542 | 0.368834 |
| oren_obc | 0.901079 | 0.901099 | 0.900286 | 0.901824 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17334272 | 17334272 | 17334272 | 17334272 |
| oren_c | 97484800 | 97488076 | 97484800 | 97501184 |
| oren_native | 33996800 | 33996800 | 33996800 | 33996800 |
| oren_obc | 135757824 | 135757824 | 135741440 | 135774208 |

Output checksum (stdout): `507588000000`
