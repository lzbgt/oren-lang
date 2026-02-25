# alloc_drop benchmark (20260225_185704)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 44c0c215a0d1ea12fe55de5ddac1d121ebb9642d
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003010 | 0.003000 | 0.002901 | 0.003055 |
| oren_c | 0.002485 | 0.002520 | 0.002446 | 0.002635 |
| oren_native | 0.006927 | 0.007036 | 0.006736 | 0.007407 |
| oren_obc | 0.004161 | 0.004152 | 0.003971 | 0.004343 |

Output checksum (stdout): `alloc_drop keep=11`
