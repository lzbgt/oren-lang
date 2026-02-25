# array_sum_int benchmark (20260225_185710)

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
| c | 0.004684 | 0.004562 | 0.004259 | 0.004749 |
| oren_c | 0.009492 | 0.009377 | 0.008972 | 0.009634 |
| oren_native | 0.017554 | 0.017463 | 0.017028 | 0.017902 |
| oren_obc | 0.264535 | 0.264059 | 0.261829 | 0.264817 |

Output checksum (stdout): `999000000`
