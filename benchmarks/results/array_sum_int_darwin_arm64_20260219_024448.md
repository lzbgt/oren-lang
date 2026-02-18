# array_sum_int benchmark (20260219_024448)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 5a8f5ba8244a68f5a47bb688a3927ab3c8176fd9
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003710 | 0.003713 | 0.003646 | 0.003785 |
| oren_c | 0.120190 | 0.120153 | 0.119721 | 0.120576 |
| oren_native | 0.151673 | 0.151776 | 0.151347 | 0.152483 |
| oren_obc | 0.627180 | 0.627292 | 0.625631 | 0.628771 |

Output checksum (stdout): `999000000`
