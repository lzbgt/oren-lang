# dot_product_int benchmark (20260219_022344)

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
| c | 0.004910 | 0.004890 | 0.004669 | 0.005249 |
| oren_c | 0.189702 | 0.189956 | 0.189468 | 0.191028 |
| oren_native | 0.358973 | 0.358897 | 0.357952 | 0.359643 |
| oren_obc | 0.898987 | 0.898714 | 0.896036 | 0.900087 |

Output checksum (stdout): `507588000000`
