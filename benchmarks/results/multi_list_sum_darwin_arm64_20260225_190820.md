# multi_list_sum benchmark (20260225_190820)

## Host

- host: Bruce-Mac
- platform: macOS-26.3-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a3c06ecdb5368e072db5ddc09c1b151ebe8666c7
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008515 | 0.008488 | 0.008176 | 0.008842 |
| oren_c | 0.036903 | 0.036857 | 0.036382 | 0.037118 |
| oren_native | 0.027307 | 0.027403 | 0.027038 | 0.028155 |
| oren_obc | 0.523693 | 0.522420 | 0.517025 | 0.528012 |

Output checksum (stdout): `2995000000`
