# dot_product benchmark (20260220_162119)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 54bd38a49b4173153227102c4117f528312ffaae
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005157 | 0.005174 | 0.004906 | 0.005561 |
| oren_c | 0.013828 | 0.013819 | 0.013676 | 0.013890 |
| oren_native | 0.021133 | 0.021008 | 0.020560 | 0.021234 |
| oren_obc | 0.376362 | 0.376914 | 0.374895 | 0.379994 |

Output checksum (stdout): `507588000000`
