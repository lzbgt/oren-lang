# alloc_drop benchmark (20260220_115810)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: d36e3104d1cca3ea93693d302f882f418541d5db
- runs: 5 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002738 | 0.002713 | 0.002630 | 0.002811 |
| oren_c | 0.004412 | 0.004501 | 0.004275 | 0.004985 |
| oren_native | 0.156371 | 0.156275 | 0.153460 | 0.159550 |
| oren_obc | 0.006830 | 0.006939 | 0.006602 | 0.007575 |

Output checksum (stdout): `alloc_drop keep=11`
