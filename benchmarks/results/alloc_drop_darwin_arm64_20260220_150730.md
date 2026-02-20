# alloc_drop benchmark (20260220_150730)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 999d9a6b0b2ceda4f0c2a9161b032b4cc6b916b2
- runs: 1 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003430 | 0.003430 | 0.003430 | 0.003430 |
| oren_c | 0.004771 | 0.004771 | 0.004771 | 0.004771 |
| oren_native | 6.811848 | 6.811848 | 6.811848 | 6.811848 |
| oren_obc | 0.007038 | 0.007038 | 0.007038 | 0.007038 |

Output checksum (stdout): `alloc_drop keep=11`
