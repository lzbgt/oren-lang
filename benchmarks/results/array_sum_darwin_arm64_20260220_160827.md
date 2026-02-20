# array_sum benchmark (20260220_160827)

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
| c | 0.004086 | 0.004153 | 0.003852 | 0.004749 |
| oren_c | 0.008592 | 0.008645 | 0.008283 | 0.009091 |
| oren_native | 1.356099 | 1.359199 | 1.350902 | 1.380359 |
| oren_obc | 0.151142 | 0.151518 | 0.149537 | 0.154275 |

Output checksum (stdout): `999000000`
