# dot_product_int benchmark (20260219_012933)

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
| c | 0.006402 | 0.006429 | 0.006232 | 0.006790 |
| oren_c | 0.359003 | 0.359145 | 0.357246 | 0.361791 |
| oren_native | 0.362066 | 0.363251 | 0.361636 | 0.368317 |
| oren_obc | 0.904473 | 0.905297 | 0.901937 | 0.908352 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17334272 | 17334272 | 17334272 | 17334272 |
| oren_c | 97746944 | 97746944 | 97746944 | 97746944 |
| oren_native | 33996800 | 33996800 | 33996800 | 33996800 |
| oren_obc | 135741440 | 135744716 | 135741440 | 135757824 |

Output checksum (stdout): `507588000000`
