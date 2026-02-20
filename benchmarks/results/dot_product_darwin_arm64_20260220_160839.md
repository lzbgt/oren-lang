# dot_product benchmark (20260220_160839)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0230b8bbb3cd37b357bc05ee43dbb79b6a85bb9e
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.005224 | 0.005225 | 0.005002 | 0.005446 |
| oren_c | 0.013906 | 0.013897 | 0.013584 | 0.014230 |
| oren_native | 2.701340 | 2.702512 | 2.700105 | 2.706285 |
| oren_obc | 0.378694 | 0.378307 | 0.377211 | 0.378799 |

Output checksum (stdout): `507588000000`
