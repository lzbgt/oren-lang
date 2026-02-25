# dot_product benchmark (20260226_042830)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: c7e8410e2a31a7c5e2073d63e11662c3ebb3fef0
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=dot_product,array_sum,multi_list_sum
- OREN_BENCH_UPDATE_LATEST=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005037 | 0.005033 | 0.004984 | 0.005083 |
| oren_c | 0.013096 | 0.013228 | 0.013013 | 0.013743 |
| oren_native | 0.012924 | 0.012890 | 0.012609 | 0.013044 |
| oren_obc | 0.412298 | 0.411926 | 0.409045 | 0.413281 |

Output checksum (stdout): `507588000000`
