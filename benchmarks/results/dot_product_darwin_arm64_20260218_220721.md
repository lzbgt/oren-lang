# dot_product benchmark (20260218_220721)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: fb674fedc890d09f720f49d43ce1553fe7af5ff7
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004987 | 0.004984 | 0.004922 | 0.005042 |
| oren_c | 0.323785 | 0.324142 | 0.322607 | 0.325773 |
| oren_native | 0.230912 | 0.231324 | 0.230374 | 0.232310 |
| oren_obc | 1.108384 | 1.051874 | 0.936891 | 1.135311 |

Output checksum (stdout): `507588000000`
