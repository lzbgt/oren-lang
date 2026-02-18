# array_sum benchmark (20260218_220638)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: fb674fedc890d09f720f49d43ce1553fe7af5ff7
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004167 | 0.004135 | 0.004050 | 0.004198 |
| oren_c | 0.189411 | 0.189419 | 0.188475 | 0.190907 |
| oren_native | 0.150609 | 0.149914 | 0.148010 | 0.151498 |
| oren_obc | 0.652288 | 0.653108 | 0.651077 | 0.656146 |

Output checksum (stdout): `999000000`
