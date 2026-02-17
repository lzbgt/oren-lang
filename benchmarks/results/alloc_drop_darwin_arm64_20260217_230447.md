# alloc_drop benchmark (20260217_230447)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 42556c6eeb9f66f6d08ac7d3028dbdf1e3ce2580
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008745 | 0.008745 | 0.008745 | 0.008745 |
| oren_c | 0.040735 | 0.040735 | 0.040735 | 0.040735 |
| oren_native | 120.601534 | 120.601534 | 120.601534 | 120.601534 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 1310720 | 1310720 | 1310720 | 1310720 |
| oren_c | 24821760 | 24821760 | 24821760 | 24821760 |
| oren_native | 15925248 | 15925248 | 15925248 | 15925248 |

Output checksum (stdout): `alloc_drop keep=10`
