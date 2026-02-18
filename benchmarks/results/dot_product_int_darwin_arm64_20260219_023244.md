# dot_product_int benchmark (20260219_023244)

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
| c | 0.004777 | 0.004887 | 0.004768 | 0.005311 |
| oren_c | 0.187978 | 0.187974 | 0.186639 | 0.189478 |
| oren_native | 0.362284 | 0.362291 | 0.359932 | 0.363999 |
| oren_obc | 0.902063 | 0.904978 | 0.900288 | 0.915560 |

Output checksum (stdout): `507588000000`
