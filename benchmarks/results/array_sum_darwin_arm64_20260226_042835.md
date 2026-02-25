# array_sum benchmark (20260226_042835)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: c7e8410e2a31a7c5e2073d63e11662c3ebb3fef0
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=dot_product,array_sum,multi_list_sum
- OREN_BENCH_UPDATE_LATEST=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004047 | 0.004058 | 0.003969 | 0.004196 |
| oren_c | 0.007922 | 0.007933 | 0.007750 | 0.008216 |
| oren_native | 0.008590 | 0.008561 | 0.008381 | 0.008767 |
| oren_obc | 0.283780 | 0.286630 | 0.280141 | 0.297196 |

Output checksum (stdout): `999000000`
