# dot_product benchmark (20260226_025024)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: fb19789ed2ceb7ef2ccff76a96a66de60d6bc967
- runs: 5 (warmups: 1)

## Env (OREN_*)

- OREN_BENCH_PROGRAMS=dot_product,dot_product_int
- OREN_BENCH_UPDATE_LATEST=1
- OREN_BENCH_UPDATE_LATEST_PRUNE=1

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005182 | 0.005171 | 0.005031 | 0.005281 |
| oren_c | 0.012953 | 0.012978 | 0.012733 | 0.013254 |
| oren_native | 0.021263 | 0.021225 | 0.021049 | 0.021318 |
| oren_obc | 0.384511 | 0.383307 | 0.379317 | 0.385711 |

Output checksum (stdout): `507588000000`
