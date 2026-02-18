# dot_product_int benchmark (20260219_032701)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: f3fe9afc19e64fd8aefc265b0279232dc31639bb
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004786 | 0.004892 | 0.004743 | 0.005337 |
| oren_c | 0.116787 | 0.116722 | 0.116373 | 0.117077 |
| oren_native | 0.285780 | 0.285771 | 0.284908 | 0.287053 |
| oren_obc | 0.898555 | 0.898465 | 0.896302 | 0.900936 |

Output checksum (stdout): `507588000000`
