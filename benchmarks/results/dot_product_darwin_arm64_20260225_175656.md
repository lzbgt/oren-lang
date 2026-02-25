# dot_product benchmark (20260225_175656)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 95a8614b5da3d9ddac233fcc732b8488c90ab4da
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005383 | 0.005301 | 0.004942 | 0.005632 |
| oren_c | 0.014659 | 0.014388 | 0.013652 | 0.014880 |
| oren_native | 0.022324 | 0.022270 | 0.022071 | 0.022429 |
| oren_obc | 0.386750 | 0.386472 | 0.382459 | 0.390331 |

Output checksum (stdout): `507588000000`
