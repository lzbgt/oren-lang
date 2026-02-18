# array_sum benchmark (20260218_133631)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: d006e24d30e524bc80a33ca988c41785397be3b4
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004182 | 0.004196 | 0.003937 | 0.004527 |
| oren_c | 0.185479 | 0.185574 | 0.185180 | 0.186506 |
| oren_native | 0.143485 | 0.143472 | 0.142812 | 0.144235 |
| oren_obc | 0.629499 | 0.630229 | 0.628574 | 0.632610 |

Output checksum (stdout): `999000000`
