# multi_list_push_int benchmark (20260225_233632)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 3be1b4679a1c76b14e25fcfcb3a75bd8c32b9c41
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAM=all
- OREN_BENCH_UPDATE_LATEST=1
- OREN_BENCH_UPDATE_LATEST_PRUNE=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.009164 | 0.009176 | 0.008822 | 0.009648 |
| oren_c | 0.040005 | 0.040116 | 0.039525 | 0.040654 |
| oren_native | 0.029287 | 0.029253 | 0.028870 | 0.029464 |
| oren_obc | 0.526419 | 0.526582 | 0.524331 | 0.529797 |

Output checksum (stdout): `2995000000`
