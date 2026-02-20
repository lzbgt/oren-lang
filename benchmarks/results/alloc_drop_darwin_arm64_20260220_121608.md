# alloc_drop benchmark (20260220_121608)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 8d5cb1abe24f680a35de01727ce79f2dc0722c79
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002867 | 0.002868 | 0.002633 | 0.003109 |
| oren_c | 0.004605 | 0.004689 | 0.004310 | 0.005231 |
| oren_native | 0.145492 | 0.145702 | 0.144174 | 0.147323 |
| oren_obc | 0.006612 | 0.006644 | 0.006565 | 0.006796 |

Output checksum (stdout): `alloc_drop keep=11`
