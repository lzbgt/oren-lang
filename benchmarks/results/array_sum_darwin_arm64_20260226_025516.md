# array_sum benchmark (20260226_025516)

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
| c | 0.004559 | 0.004578 | 0.004235 | 0.005000 |
| oren_c | 0.009189 | 0.009310 | 0.008968 | 0.010021 |
| oren_native | 0.016502 | 0.016392 | 0.016092 | 0.016626 |
| oren_obc | 0.256702 | 0.257169 | 0.254487 | 0.260349 |

Output checksum (stdout): `999000000`
