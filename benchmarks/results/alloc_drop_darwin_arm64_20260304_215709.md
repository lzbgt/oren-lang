# alloc_drop benchmark (20260304_215709)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 03ca7970980f6bc042a2599fb02eb7c38951a593
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=alloc_churn,alloc_drop

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002953 | 0.002958 | 0.002865 | 0.003088 |
| oren_c | 0.002461 | 0.002442 | 0.002324 | 0.002551 |
| oren_native | 0.004275 | 0.004293 | 0.004238 | 0.004374 |
| oren_obc | 0.003854 | 0.003898 | 0.003792 | 0.004174 |

Output checksum (stdout): `alloc_drop keep=11`
