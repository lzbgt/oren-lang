# array_sum benchmark (20260219_223724)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0efd12524e37274075e0cb44e30fe4f484d861ea
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003892 | 0.003973 | 0.003814 | 0.004303 |
| oren_c | 0.008553 | 0.008506 | 0.008129 | 0.008727 |
| oren_native | 0.014779 | 0.014831 | 0.014579 | 0.015287 |
| oren_obc | 0.009161 | 0.009061 | 0.008785 | 0.009278 |

Output checksum (stdout): `999000000`
