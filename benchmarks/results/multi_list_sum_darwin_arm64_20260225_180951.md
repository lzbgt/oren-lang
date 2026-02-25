# multi_list_sum benchmark (20260225_180951)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: b5b14c484ce0df6f7ed4eb76b20242c9fa0e6e22
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.009698 | 0.009820 | 0.009556 | 0.010126 |
| oren_c | 0.041096 | 0.041186 | 0.040960 | 0.041569 |
| oren_native | 0.029739 | 0.029621 | 0.029306 | 0.029805 |
| oren_obc | 0.531616 | 0.531203 | 0.526899 | 0.533337 |

Output checksum (stdout): `2995000000`
