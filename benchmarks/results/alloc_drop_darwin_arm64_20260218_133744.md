# alloc_drop benchmark (20260218_133744)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: d006e24d30e524bc80a33ca988c41785397be3b4
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005732 | 0.005732 | 0.005732 | 0.005732 |
| oren_c | 0.007348 | 0.007348 | 0.007348 | 0.007348 |
| oren_native | 0.281654 | 0.281654 | 0.281654 | 0.281654 |
| oren_obc | 0.011996 | 0.011996 | 0.011996 | 0.011996 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 1327104 | 1327104 | 1327104 | 1327104 |
| oren_c | 4734976 | 4734976 | 4734976 | 4734976 |
| oren_native | 7716864 | 7716864 | 7716864 | 7716864 |
| oren_obc | 9322496 | 9322496 | 9322496 | 9322496 |

Output checksum (stdout): `alloc_drop keep=11`
