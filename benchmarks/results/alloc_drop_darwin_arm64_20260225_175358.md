# alloc_drop benchmark (20260225_175358)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 305af5d016f630892d25dc7393a02281b6c67175
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002982 | 0.003056 | 0.002766 | 0.003342 |
| oren_c | 0.002605 | 0.002632 | 0.002492 | 0.002886 |
| oren_native | 0.006855 | 0.007039 | 0.006643 | 0.007648 |
| oren_obc | 0.003891 | 0.004031 | 0.003807 | 0.004421 |

Output checksum (stdout): `alloc_drop keep=11`
