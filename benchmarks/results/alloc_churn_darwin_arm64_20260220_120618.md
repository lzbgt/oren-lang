# alloc_churn benchmark (20260220_120618)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 404c1ab42e314c9d80a0038336efaec15033e840
- runs: 5 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002605 | 0.002790 | 0.002568 | 0.003517 |
| oren_c | 0.030125 | 0.030191 | 0.029974 | 0.030421 |
| oren_native | 0.340328 | 0.341663 | 0.338572 | 0.347201 |
| oren_obc | 0.162369 | 0.162468 | 0.162230 | 0.162970 |

Output checksum (stdout): `199990000`
