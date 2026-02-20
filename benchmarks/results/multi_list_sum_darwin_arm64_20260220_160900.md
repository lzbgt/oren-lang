# multi_list_sum benchmark (20260220_160900)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0230b8bbb3cd37b357bc05ee43dbb79b6a85bb9e
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.009298 | 0.009258 | 0.008615 | 0.009715 |
| oren_c | 0.039681 | 0.039609 | 0.038776 | 0.040122 |
| oren_native | 4.040096 | 4.046042 | 4.024257 | 4.073950 |
| oren_obc | 0.307973 | 0.308169 | 0.306673 | 0.309953 |

Output checksum (stdout): `2995000000`
