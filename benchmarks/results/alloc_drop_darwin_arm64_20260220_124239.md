# alloc_drop benchmark (20260220_124239)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 931f26bd456cf56d4d3444a0c23f5040d1096ba2
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002776 | 0.002792 | 0.002752 | 0.002840 |
| oren_c | 0.004395 | 0.004475 | 0.004338 | 0.004835 |
| oren_native | 0.144586 | 0.144527 | 0.142904 | 0.145773 |
| oren_obc | 0.006691 | 0.006720 | 0.006614 | 0.006881 |

Output checksum (stdout): `alloc_drop keep=11`
