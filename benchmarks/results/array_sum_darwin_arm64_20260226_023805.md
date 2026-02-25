# array_sum benchmark (20260226_023805)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: b9035ad3f494037525571658e74b4eb73361e5bd
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAM=all
- OREN_BENCH_UPDATE_LATEST=1
- OREN_BENCH_UPDATE_LATEST_PRUNE=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004445 | 0.004406 | 0.004176 | 0.004635 |
| oren_c | 0.007815 | 0.007859 | 0.007779 | 0.008042 |
| oren_native | 0.017483 | 0.017683 | 0.017258 | 0.018447 |
| oren_obc | 0.261449 | 0.261245 | 0.259466 | 0.262548 |

Output checksum (stdout): `999000000`
