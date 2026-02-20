# alloc_drop benchmark (20260220_151923)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1154b5a7662c794154ed13cc8a770627c0af5aae
- runs: 1 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002908 | 0.002908 | 0.002908 | 0.002908 |
| oren_c | 0.004601 | 0.004601 | 0.004601 | 0.004601 |
| oren_native | 0.175708 | 0.175708 | 0.175708 | 0.175708 |
| oren_obc | 0.007426 | 0.007426 | 0.007426 | 0.007426 |

Output checksum (stdout): `alloc_drop keep=11`
