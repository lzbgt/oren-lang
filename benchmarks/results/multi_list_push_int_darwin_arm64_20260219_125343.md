# multi_list_push_int benchmark (20260219_125343)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 7a152c49e074a98b0d667a852a82741dc0620568
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.010435 | 0.010349 | 0.009562 | 0.011235 |
| oren_c | 0.041430 | 0.041625 | 0.040527 | 0.042763 |
| oren_native | 0.034321 | 0.034156 | 0.033204 | 0.035065 |
| oren_obc | 0.012781 | 0.012673 | 0.012305 | 0.013156 |

Output checksum (stdout): `2995000000`
