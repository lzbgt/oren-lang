# array_sum benchmark (20260225_185706)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 44c0c215a0d1ea12fe55de5ddac1d121ebb9642d
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004552 | 0.004536 | 0.004471 | 0.004574 |
| oren_c | 0.009409 | 0.009414 | 0.008732 | 0.009808 |
| oren_native | 0.017886 | 0.017899 | 0.017802 | 0.018060 |
| oren_obc | 0.272239 | 0.272773 | 0.266518 | 0.281924 |

Output checksum (stdout): `999000000`
