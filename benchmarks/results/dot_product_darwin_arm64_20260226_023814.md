# dot_product benchmark (20260226_023814)

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
| c | 0.005442 | 0.005497 | 0.005391 | 0.005633 |
| oren_c | 0.012820 | 0.012753 | 0.012561 | 0.012975 |
| oren_native | 0.023512 | 0.023305 | 0.022414 | 0.023848 |
| oren_obc | 0.388749 | 0.389243 | 0.388017 | 0.391772 |

Output checksum (stdout): `507588000000`
