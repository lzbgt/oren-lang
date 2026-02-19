# dot_product benchmark (20260220_042056)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: f2fcc8abe0025a6cc88b3f20199669e9794e736c
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005163 | 0.005139 | 0.005061 | 0.005202 |
| oren_c | 0.012716 | 0.012648 | 0.012392 | 0.012821 |
| oren_native | 0.027416 | 0.027587 | 0.027032 | 0.028263 |
| oren_obc | 0.012794 | 0.012669 | 0.012139 | 0.012995 |

Output checksum (stdout): `507588000000`
