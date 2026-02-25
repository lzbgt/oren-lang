# alloc_churn benchmark (20260226_022314)

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
| c | 0.002974 | 0.002943 | 0.002797 | 0.003038 |
| oren_c | 0.012214 | 0.012235 | 0.012072 | 0.012432 |
| oren_native | 0.017783 | 0.017778 | 0.017652 | 0.017962 |
| oren_obc | 0.163190 | 0.162861 | 0.160873 | 0.164965 |

Output checksum (stdout): `199990000`
