# alloc_churn benchmark (20260304_215704)

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
| c | 0.002775 | 0.002868 | 0.002731 | 0.003230 |
| oren_c | 0.049681 | 0.049857 | 0.048766 | 0.051851 |
| oren_native | 0.063258 | 0.063403 | 0.062179 | 0.064714 |
| oren_obc | 0.271996 | 0.272586 | 0.269011 | 0.276131 |

Output checksum (stdout): `199990000`
