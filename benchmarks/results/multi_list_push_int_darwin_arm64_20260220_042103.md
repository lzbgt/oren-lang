# multi_list_push_int benchmark (20260220_042103)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: f2fcc8abe0025a6cc88b3f20199669e9794e736c
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.009168 | 0.009037 | 0.008661 | 0.009334 |
| oren_c | 0.037586 | 0.037820 | 0.037338 | 0.038639 |
| oren_native | 0.028363 | 0.028399 | 0.027908 | 0.028976 |
| oren_obc | 0.011138 | 0.011254 | 0.010883 | 0.011666 |

Output checksum (stdout): `2995000000`
