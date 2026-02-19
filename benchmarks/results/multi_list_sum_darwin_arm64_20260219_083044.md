# multi_list_sum benchmark (20260219_083044)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: b5004cb2c55381bc19411af038d347808bf5f4d9
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008383 | 0.008481 | 0.008351 | 0.008693 |
| oren_c | 0.025794 | 0.025944 | 0.025609 | 0.026645 |
| oren_native | 0.030489 | 0.030345 | 0.029920 | 0.030656 |
| oren_obc | 1.228532 | 1.228084 | 1.224201 | 1.231952 |

Output checksum (stdout): `2995000000`
