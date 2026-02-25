# multi_list_sum benchmark (20260226_042839)

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
| c | 0.008222 | 0.008207 | 0.008067 | 0.008315 |
| oren_c | 0.037745 | 0.037917 | 0.037202 | 0.039063 |
| oren_native | 0.019307 | 0.019318 | 0.018926 | 0.019583 |
| oren_obc | 0.575606 | 0.575936 | 0.573250 | 0.579308 |

Output checksum (stdout): `2995000000`
