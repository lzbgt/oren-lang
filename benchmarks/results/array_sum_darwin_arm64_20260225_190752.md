# array_sum benchmark (20260225_190752)

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
| c | 0.004043 | 0.004072 | 0.003988 | 0.004154 |
| oren_c | 0.007865 | 0.007835 | 0.007592 | 0.007984 |
| oren_native | 0.016664 | 0.016630 | 0.016399 | 0.016820 |
| oren_obc | 0.255961 | 0.255914 | 0.252805 | 0.258669 |

Output checksum (stdout): `999000000`
