# array_sum_int benchmark (20260226_023809)

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
| c | 0.004736 | 0.004486 | 0.003984 | 0.004975 |
| oren_c | 0.008356 | 0.008387 | 0.008196 | 0.008597 |
| oren_native | 0.017691 | 0.017751 | 0.017388 | 0.018222 |
| oren_obc | 0.263454 | 0.267668 | 0.260921 | 0.278244 |

Output checksum (stdout): `999000000`
