# array_sum_int benchmark (20260219_023233)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: fbb3b0e6d58ce55b5dcd56f1760d1de5c350baef
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003753 | 0.003832 | 0.003686 | 0.004216 |
| oren_c | 0.119836 | 0.119843 | 0.119350 | 0.120390 |
| oren_native | 0.214117 | 0.213626 | 0.210665 | 0.216716 |
| oren_obc | 0.629634 | 0.629464 | 0.625114 | 0.634216 |

Output checksum (stdout): `999000000`
