# alloc_drop benchmark (20260220_120356)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: eaf6d8dbafacbe8ba28112f322387fe81a63bafd
- runs: 5 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002723 | 0.002771 | 0.002686 | 0.002974 |
| oren_c | 0.004434 | 0.004557 | 0.004400 | 0.005073 |
| oren_native | 0.154535 | 0.154752 | 0.150947 | 0.158131 |
| oren_obc | 0.006704 | 0.007067 | 0.006636 | 0.008562 |

Output checksum (stdout): `alloc_drop keep=11`
