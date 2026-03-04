# alloc_drop benchmark (20260304_235152)

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
| c | 0.002986 | 0.003063 | 0.002828 | 0.003327 |
| oren_c | 0.002645 | 0.002676 | 0.002495 | 0.002875 |
| oren_native | 0.004703 | 0.004616 | 0.004330 | 0.004804 |
| oren_obc | 0.003935 | 0.003988 | 0.003833 | 0.004390 |

Output checksum (stdout): `alloc_drop keep=11`
