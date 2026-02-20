# alloc_drop benchmark (20260220_123822)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: b21bb0cfbf2d0672879a4778a54d10d0740aff66
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002746 | 0.002874 | 0.002693 | 0.003371 |
| oren_c | 0.004325 | 0.004342 | 0.004282 | 0.004449 |
| oren_native | 0.149931 | 0.149012 | 0.146273 | 0.150328 |
| oren_obc | 0.006640 | 0.006636 | 0.006497 | 0.006739 |

Output checksum (stdout): `alloc_drop keep=11`
