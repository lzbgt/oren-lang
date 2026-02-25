# dot_product benchmark (20260225_182212)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1e81dc28a1d4d88d1e1ddc63949a1f6780bedd28
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.006015 | 0.005958 | 0.005734 | 0.006129 |
| oren_c | 0.013981 | 0.013973 | 0.013346 | 0.014598 |
| oren_native | 0.023907 | 0.023891 | 0.023530 | 0.024176 |
| oren_obc | 0.416495 | 0.417702 | 0.396082 | 0.443397 |

Output checksum (stdout): `507588000000`
