# dot_product benchmark (20260219_130440)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: e6ce345aed3e647a88a133e0f3704171f21e97f2
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005407 | 0.005320 | 0.005087 | 0.005472 |
| oren_c | 0.012672 | 0.012772 | 0.012273 | 0.013151 |
| oren_native | 0.025681 | 0.025552 | 0.025069 | 0.025914 |
| oren_obc | 0.012785 | 0.012889 | 0.012491 | 0.013478 |

Output checksum (stdout): `507588000000`
