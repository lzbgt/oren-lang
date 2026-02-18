# array_sum benchmark (20260218_221223)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 7f987dbcc434d6b0276194f5a41cf5be17c01b79
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003986 | 0.003999 | 0.003889 | 0.004210 |
| oren_c | 0.190177 | 0.190734 | 0.189400 | 0.193583 |
| oren_native | 0.148220 | 0.148060 | 0.147463 | 0.148278 |
| oren_obc | 0.661548 | 0.711603 | 0.645104 | 0.836986 |

Output checksum (stdout): `999000000`
