# multi_list_push_int benchmark (20260220_105047)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: ea30b50a2c9482a01f8485e45c0bc42944757135
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008798 | 0.008837 | 0.008765 | 0.009030 |
| oren_c | 0.038419 | 0.038201 | 0.037611 | 0.038673 |
| oren_native | 0.027695 | 0.027746 | 0.027259 | 0.028456 |
| oren_obc | 0.011052 | 0.011097 | 0.010995 | 0.011234 |

Output checksum (stdout): `2995000000`
