# alloc_drop benchmark (20260226_020709)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1654d68d96a0c07a95120ee74db84ce0de22aaa6
- runs: 3 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_ENV_BUILD_OREN=OREN_OPT_LOOP_LIST_REUSE=1
- OREN_BENCH_PROGRAMS=alloc_drop
- OREN_BENCH_RUNS=3
- OREN_BENCH_SKIP_OBC=1
- OREN_BENCH_WARMUPS=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002975 | 0.002970 | 0.002909 | 0.003027 |
| oren_c | 0.002572 | 0.002628 | 0.002554 | 0.002758 |
| oren_native | 0.007614 | 0.007598 | 0.007401 | 0.007778 |

Output checksum (stdout): `alloc_drop keep=11`
