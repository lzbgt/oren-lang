# alloc_churn benchmark (20260304_233032)

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
| c | 0.002737 | 0.002722 | 0.002666 | 0.002773 |
| oren_c | 0.047325 | 0.047388 | 0.045665 | 0.049517 |
| oren_native | 0.285658 | 0.286885 | 0.285176 | 0.291023 |
| oren_obc | 0.270297 | 0.271255 | 0.268045 | 0.276466 |

Output checksum (stdout): `199990000`
