# dot_product benchmark (20260226_025518)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 75f695ab214213e86671a4c86837c26debe48cb7
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=array_sum,dot_product
- OREN_BENCH_UPDATE_LATEST=1
- OREN_BENCH_UPDATE_LATEST_PRUNE=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005299 | 0.005282 | 0.005128 | 0.005438 |
| oren_c | 0.014907 | 0.014768 | 0.014103 | 0.015424 |
| oren_native | 0.022779 | 0.022785 | 0.022539 | 0.023194 |
| oren_obc | 0.385132 | 0.382760 | 0.378313 | 0.385869 |

Output checksum (stdout): `507588000000`
