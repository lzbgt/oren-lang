# alloc_drop benchmark (20260304_233036)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 02324f76077966d58638a26af3d863d90bbce605
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=alloc_churn,alloc_drop

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002948 | 0.002971 | 0.002814 | 0.003170 |
| oren_c | 0.002571 | 0.002630 | 0.002466 | 0.002977 |
| oren_native | 0.004343 | 0.004376 | 0.004200 | 0.004588 |
| oren_obc | 0.004541 | 0.004535 | 0.003953 | 0.004886 |

Output checksum (stdout): `alloc_drop keep=11`
