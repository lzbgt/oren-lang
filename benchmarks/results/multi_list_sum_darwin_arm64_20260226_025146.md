# multi_list_sum benchmark (20260226_025146)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 660bfd043983caf1bbd3b01dcb6bb4d6b0cecde1
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=array_sum_int,multi_list_sum
- OREN_BENCH_UPDATE_LATEST=1
- OREN_BENCH_UPDATE_LATEST_PRUNE=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008727 | 0.008728 | 0.008621 | 0.008877 |
| oren_c | 0.040382 | 0.040221 | 0.039452 | 0.040659 |
| oren_native | 0.027744 | 0.027762 | 0.027267 | 0.028436 |
| oren_obc | 0.531214 | 0.529354 | 0.524419 | 0.531806 |

Output checksum (stdout): `2995000000`
