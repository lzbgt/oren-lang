# alloc_drop benchmark (20260217_225558)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 17222c6b605d6eacd1427e597e31ae5b0c442d5d
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.007730 | 0.007730 | 0.007730 | 0.007730 |
| oren_c | 0.019035 | 0.019035 | 0.019035 | 0.019035 |
| oren_native | 0.734199 | 0.734199 | 0.734199 | 0.734199 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 1310720 | 1310720 | 1310720 | 1310720 |
| oren_c | 9863168 | 9863168 | 9863168 | 9863168 |
| oren_native | 13500416 | 13500416 | 13500416 | 13500416 |

Output checksum (stdout): `alloc_drop keep=11`
