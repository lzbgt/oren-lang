# dot_product benchmark (20260219_002549)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 0019373d6f61ff78e0bfdc6530183f2c9bf44c37
- runs: 3 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.007177 | 0.007144 | 0.007000 | 0.007256 |
| oren_c | 0.333380 | 0.334032 | 0.321089 | 0.347627 |
| oren_native | 0.231631 | 0.231892 | 0.231216 | 0.232828 |
| oren_obc | 0.967149 | 0.968939 | 0.965736 | 0.973932 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17350656 | 17350656 | 17350656 | 17350656 |
| oren_c | 153452544 | 153447082 | 153436160 | 153452544 |
| oren_native | 67518464 | 67518464 | 67518464 | 67518464 |
| oren_obc | 135774208 | 135779669 | 135774208 | 135790592 |

Output checksum (stdout): `507588000000`
