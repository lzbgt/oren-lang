# dot_product benchmark (20260305_021919)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: bbd4dabc91ba7522b7f7aff76e548a10a32adc6e
- runs: 3 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=loop_sum,dot_product
- OREN_BENCH_RUNS=3
- OREN_BENCH_SKIP_OBC=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005185 | 0.005159 | 0.005058 | 0.005234 |
| oren_c | 0.014056 | 0.013992 | 0.013429 | 0.014490 |
| oren_native | 0.013571 | 0.013602 | 0.013330 | 0.013906 |

Output checksum (stdout): `507588000000`
