# alloc_churn benchmark (20260304_235146)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 705cdb7758724518578fcf75156487f8c27ef0be
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=alloc_churn,alloc_drop

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002886 | 0.002885 | 0.002841 | 0.002938 |
| oren_c | 0.044964 | 0.045161 | 0.044712 | 0.045861 |
| oren_native | 0.015997 | 0.016112 | 0.015836 | 0.016700 |
| oren_obc | 0.270125 | 0.278453 | 0.268311 | 0.313671 |

Output checksum (stdout): `199990000`
