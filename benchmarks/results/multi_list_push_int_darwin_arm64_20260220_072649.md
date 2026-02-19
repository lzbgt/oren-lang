# multi_list_push_int benchmark (20260220_072649)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: adb813e9f6902370fd3c103af2d873d6f02782b5
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008929 | 0.008934 | 0.008754 | 0.009144 |
| oren_c | 0.038942 | 0.038879 | 0.038525 | 0.039335 |
| oren_native | 0.028508 | 0.028674 | 0.028365 | 0.029317 |
| oren_obc | 0.011714 | 0.011586 | 0.011193 | 0.011879 |

Output checksum (stdout): `2995000000`
