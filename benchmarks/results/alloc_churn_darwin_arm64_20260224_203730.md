# alloc_churn benchmark (20260224_203730)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 20bc02b36b682e0711daf4f0cf8b753e138ef415
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003029 | 0.003054 | 0.002985 | 0.003189 |
| oren_c | 0.032142 | 0.032187 | 0.031821 | 0.032587 |
| oren_native | 4.433411 | 4.488741 | 4.416773 | 4.636343 |
| oren_obc | 0.173998 | 0.174471 | 0.172825 | 0.176567 |

Output checksum (stdout): `199990000`
