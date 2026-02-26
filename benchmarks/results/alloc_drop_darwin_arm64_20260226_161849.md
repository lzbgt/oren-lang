# alloc_drop benchmark (20260226_161849)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: c43993469b865c61ad2b68cf3bfbb421a126c608
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=alloc_churn,alloc_drop

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003361 | 0.003376 | 0.003261 | 0.003474 |
| oren_c | 0.002786 | 0.003102 | 0.002745 | 0.004374 |
| oren_native | 0.004313 | 0.004302 | 0.004177 | 0.004439 |
| oren_obc | 0.004304 | 0.004344 | 0.004226 | 0.004530 |

Output checksum (stdout): `alloc_drop keep=11`
