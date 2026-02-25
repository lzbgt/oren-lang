# alloc_churn benchmark (20260225_190747)

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
| c | 0.002713 | 0.002848 | 0.002645 | 0.003481 |
| oren_c | 0.012436 | 0.012619 | 0.012077 | 0.013329 |
| oren_native | 0.019613 | 0.019343 | 0.018716 | 0.019798 |
| oren_obc | 0.161827 | 0.162126 | 0.159276 | 0.165795 |

Output checksum (stdout): `199990000`
