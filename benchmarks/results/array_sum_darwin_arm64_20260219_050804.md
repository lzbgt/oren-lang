# array_sum benchmark (20260219_050804)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 5da2243f97a31a8c0a993e91bd3f9f6dcc0527a5
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.006021 | 0.006135 | 0.005520 | 0.006793 |
| oren_c | 0.116454 | 0.116774 | 0.116335 | 0.117417 |
| oren_native | 0.145107 | 0.145050 | 0.144349 | 0.145756 |
| oren_obc | 0.626310 | 0.626477 | 0.622751 | 0.632742 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 17317888 | 17321164 | 17317888 | 17334272 |
| oren_c | 51150848 | 51150848 | 51150848 | 51150848 |
| oren_native | 34717696 | 34717696 | 34717696 | 34717696 |
| oren_obc | 70582272 | 70582272 | 70565888 | 70598656 |

Output checksum (stdout): `999000000`
