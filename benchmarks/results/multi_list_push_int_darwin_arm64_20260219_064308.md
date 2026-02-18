# multi_list_push_int benchmark (20260219_064308)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a8e448776d4a082a094b95f1f38e04e7a04eabfc
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008319 | 0.008458 | 0.008156 | 0.009024 |
| oren_c | 0.079181 | 0.079907 | 0.078427 | 0.081736 |
| oren_native | 0.031168 | 0.031942 | 0.031084 | 0.033589 |
| oren_obc | 1.227477 | 1.226569 | 1.224414 | 1.228001 |

Output checksum (stdout): `2995000000`
