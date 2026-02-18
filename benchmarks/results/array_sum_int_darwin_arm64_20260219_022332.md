# array_sum_int benchmark (20260219_022332)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: fbb3b0e6d58ce55b5dcd56f1760d1de5c350baef
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003798 | 0.003993 | 0.003748 | 0.004365 |
| oren_c | 0.120936 | 0.121254 | 0.120722 | 0.121929 |
| oren_native | 0.211424 | 0.211016 | 0.209261 | 0.212638 |
| oren_obc | 0.628249 | 0.629618 | 0.627236 | 0.636079 |

Output checksum (stdout): `999000000`
