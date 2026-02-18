# alloc_drop benchmark (20260219_041618)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 7ed08094fca7e89b239fef32f4e964fe0b0ecd77
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004245 | 0.004248 | 0.004073 | 0.004367 |
| oren_c | 0.006711 | 0.006787 | 0.006686 | 0.007128 |
| oren_native | 0.265620 | 0.265415 | 0.258926 | 0.270814 |
| oren_obc | 0.010976 | 0.010937 | 0.010581 | 0.011218 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 1327104 | 1327104 | 1327104 | 1327104 |
| oren_c | 4472832 | 4472832 | 4472832 | 4472832 |
| oren_native | 7766016 | 7766016 | 7766016 | 7766016 |
| oren_obc | 9355264 | 9348710 | 9338880 | 9355264 |

Output checksum (stdout): `alloc_drop keep=11`
