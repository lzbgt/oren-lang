# multi_list_sum benchmark (20260220_161447)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: eb68efa24b86bbb37dc2f3c7c5bac65b3bf9e8af
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008670 | 0.008518 | 0.008041 | 0.008896 |
| oren_c | 0.036617 | 0.036841 | 0.036497 | 0.037901 |
| oren_native | 0.026429 | 0.026336 | 0.025831 | 0.026703 |
| oren_obc | 0.304140 | 0.305285 | 0.303286 | 0.307770 |

Output checksum (stdout): `2995000000`
