# multi_list_push_int benchmark (20260219_123742)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 6aff4dfa29b756db6ec51040a51c7591553667f2
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008529 | 0.008616 | 0.008021 | 0.009266 |
| oren_c | 0.083179 | 0.083995 | 0.082981 | 0.087225 |
| oren_native | 0.032209 | 0.032006 | 0.031492 | 0.032422 |
| oren_obc | 0.011110 | 0.011156 | 0.010873 | 0.011454 |

Output checksum (stdout): `2995000000`
