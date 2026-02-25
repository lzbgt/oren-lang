# multi_list_sum benchmark (20260225_233636)

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
| c | 0.009747 | 0.009789 | 0.009693 | 0.010041 |
| oren_c | 0.041721 | 0.041794 | 0.041102 | 0.042414 |
| oren_native | 0.029655 | 0.029691 | 0.028999 | 0.030580 |
| oren_obc | 0.531158 | 0.531545 | 0.527093 | 0.537314 |

Output checksum (stdout): `2995000000`
