# dot_product benchmark (20260218_221234)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 7f987dbcc434d6b0276194f5a41cf5be17c01b79
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005085 | 0.005120 | 0.004974 | 0.005366 |
| oren_c | 0.320566 | 0.320781 | 0.319253 | 0.322330 |
| oren_native | 0.227120 | 0.227253 | 0.226889 | 0.227811 |
| oren_obc | 0.929276 | 0.934868 | 0.923502 | 0.960653 |

Output checksum (stdout): `507588000000`
