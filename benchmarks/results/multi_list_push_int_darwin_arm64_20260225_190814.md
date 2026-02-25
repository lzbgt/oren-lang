# multi_list_push_int benchmark (20260225_190814)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a3c06ecdb5368e072db5ddc09c1b151ebe8666c7
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008086 | 0.008248 | 0.008032 | 0.008830 |
| oren_c | 0.036685 | 0.036651 | 0.036285 | 0.036942 |
| oren_native | 0.027417 | 0.027676 | 0.027177 | 0.028503 |
| oren_obc | 0.520932 | 0.521239 | 0.517336 | 0.525748 |

Output checksum (stdout): `2995000000`
