# array_sum benchmark (20260219_073204)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 82ec42e3fc2b066dcba190d2a14a3d325b9c187b
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003837 | 0.003850 | 0.003800 | 0.003953 |
| oren_c | 0.114373 | 0.114427 | 0.114204 | 0.114733 |
| oren_native | 0.141456 | 0.141338 | 0.140981 | 0.141487 |
| oren_obc | 0.620979 | 0.620803 | 0.618453 | 0.622618 |

Output checksum (stdout): `999000000`
