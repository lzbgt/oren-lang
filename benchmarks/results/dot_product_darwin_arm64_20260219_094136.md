# dot_product benchmark (20260219_094136)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1c813367ae4d3b88cd6a0894dfd20e96aa7abaa4
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004780 | 0.004814 | 0.004681 | 0.005102 |
| oren_c | 0.017754 | 0.017659 | 0.017329 | 0.017888 |
| oren_native | 0.024412 | 0.024364 | 0.024132 | 0.024508 |
| oren_obc | 0.547356 | 0.547324 | 0.546563 | 0.547906 |

Output checksum (stdout): `507588000000`
