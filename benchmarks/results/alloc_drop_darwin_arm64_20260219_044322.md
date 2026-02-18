# alloc_drop benchmark (20260219_044322)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1980a4851ae2269f1eea6db964bc41575b7da4b6
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004304 | 0.004292 | 0.004094 | 0.004553 |
| oren_c | 0.006573 | 0.006516 | 0.006327 | 0.006755 |
| oren_native | 0.171313 | 0.171729 | 0.170594 | 0.174085 |
| oren_obc | 0.010599 | 0.010630 | 0.010563 | 0.010806 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 1327104 | 1327104 | 1327104 | 1327104 |
| oren_c | 4472832 | 4472832 | 4472832 | 4472832 |
| oren_native | 7766016 | 7766016 | 7766016 | 7766016 |
| oren_obc | 9355264 | 9348710 | 9338880 | 9355264 |

Output checksum (stdout): `alloc_drop keep=11`
