# multi_list_sum benchmark (20260220_162123)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 54bd38a49b4173153227102c4117f528312ffaae
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008697 | 0.008688 | 0.008403 | 0.009106 |
| oren_c | 0.039939 | 0.039578 | 0.038571 | 0.040564 |
| oren_native | 0.026986 | 0.026974 | 0.026542 | 0.027340 |
| oren_obc | 0.305456 | 0.305432 | 0.303875 | 0.306783 |

Output checksum (stdout): `2995000000`
