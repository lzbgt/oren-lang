# dot_product benchmark (20260220_055840)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: e176c96a5bca2b935f78a10714c222d0080416fe
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005059 | 0.005071 | 0.004894 | 0.005258 |
| oren_c | 0.049907 | 0.049798 | 0.049542 | 0.049964 |
| oren_native | 0.054673 | 0.054599 | 0.053962 | 0.055475 |
| oren_obc | 0.248005 | 0.247687 | 0.245547 | 0.249033 |

Output checksum (stdout): `507588000000`
