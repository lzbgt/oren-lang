# dot_product benchmark (20260219_221317)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1c606f858f6f86e2df1b8ed58c22ddf20400ea57
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004874 | 0.004851 | 0.004750 | 0.004959 |
| oren_c | 0.012928 | 0.013172 | 0.012774 | 0.013631 |
| oren_native | 0.024578 | 0.024592 | 0.024441 | 0.024774 |
| oren_obc | 0.012325 | 0.012297 | 0.012111 | 0.012395 |

Output checksum (stdout): `507588000000`
