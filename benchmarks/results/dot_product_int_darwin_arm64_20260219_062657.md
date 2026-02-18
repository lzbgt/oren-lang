# dot_product_int benchmark (20260219_062657)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 60a51fc53eef5894cfb2aac11661fc0d7c7eb2e4
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004965 | 0.005071 | 0.004826 | 0.005543 |
| oren_c | 0.018847 | 0.018862 | 0.018796 | 0.018969 |
| oren_native | 0.024758 | 0.024796 | 0.024603 | 0.024982 |
| oren_obc | 0.890157 | 0.890886 | 0.889023 | 0.892692 |

Output checksum (stdout): `507588000000`
