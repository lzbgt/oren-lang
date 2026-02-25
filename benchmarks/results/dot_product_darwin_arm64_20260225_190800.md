# dot_product benchmark (20260225_190800)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a3c06ecdb5368e072db5ddc09c1b151ebe8666c7
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005063 | 0.005145 | 0.005007 | 0.005477 |
| oren_c | 0.012267 | 0.012274 | 0.011941 | 0.012658 |
| oren_native | 0.021772 | 0.021727 | 0.021476 | 0.021816 |
| oren_obc | 0.378822 | 0.378636 | 0.374901 | 0.383038 |

Output checksum (stdout): `507588000000`
