# alloc_drop benchmark (20260226_023803)

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
| c | 0.002957 | 0.002951 | 0.002885 | 0.003066 |
| oren_c | 0.002527 | 0.002579 | 0.002457 | 0.002697 |
| oren_native | 0.006985 | 0.006986 | 0.006892 | 0.007104 |
| oren_obc | 0.003942 | 0.003933 | 0.003855 | 0.003990 |

Output checksum (stdout): `alloc_drop keep=11`
