# array_sum_int benchmark (20260219_054300)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 320a90484988b41a0fc205b139707cd74dd0c627
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003825 | 0.003820 | 0.003790 | 0.003864 |
| oren_c | 0.082009 | 0.082133 | 0.081812 | 0.082442 |
| oren_native | 0.019824 | 0.019939 | 0.019713 | 0.020463 |
| oren_obc | 0.622686 | 0.622832 | 0.619946 | 0.628227 |

Output checksum (stdout): `999000000`
