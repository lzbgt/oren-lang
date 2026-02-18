# array_sum_int benchmark (20260219_055227)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 28149babb6bca751788c04af65be0c63691b6d23
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003818 | 0.003837 | 0.003799 | 0.003917 |
| oren_c | 0.065961 | 0.066090 | 0.064864 | 0.067690 |
| oren_native | 0.019952 | 0.020047 | 0.019894 | 0.020378 |
| oren_obc | 0.619605 | 0.620150 | 0.618187 | 0.623243 |

Output checksum (stdout): `999000000`
