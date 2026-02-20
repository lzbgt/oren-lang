# alloc_drop benchmark (20260220_124417)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a3a1cbca71871bbde063b9c64312e3345b3fb82a
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002836 | 0.002815 | 0.002746 | 0.002846 |
| oren_c | 0.004454 | 0.004431 | 0.004355 | 0.004454 |
| oren_native | 0.147676 | 0.147597 | 0.146467 | 0.148960 |
| oren_obc | 0.006543 | 0.006608 | 0.006516 | 0.006785 |

Output checksum (stdout): `alloc_drop keep=11`
