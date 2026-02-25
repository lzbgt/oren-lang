# alloc_drop benchmark (20260226_022316)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 097ec52cb5347bce974f3625167395a5aa06dc42
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=alloc_churn,alloc_drop
- OREN_BENCH_UPDATE_LATEST=1
- OREN_BENCH_UPDATE_LATEST_PRUNE=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002951 | 0.002934 | 0.002862 | 0.002988 |
| oren_c | 0.002516 | 0.002513 | 0.002480 | 0.002547 |
| oren_native | 0.006713 | 0.006753 | 0.006684 | 0.006835 |
| oren_obc | 0.003900 | 0.003877 | 0.003809 | 0.003920 |

Output checksum (stdout): `alloc_drop keep=11`
