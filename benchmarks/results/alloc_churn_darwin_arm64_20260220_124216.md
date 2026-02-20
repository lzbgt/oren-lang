# alloc_churn benchmark (20260220_124216)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 931f26bd456cf56d4d3444a0c23f5040d1096ba2
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002560 | 0.002584 | 0.002546 | 0.002680 |
| oren_c | 0.030046 | 0.030087 | 0.029882 | 0.030462 |
| oren_native | 3.403557 | 3.403035 | 3.398451 | 3.407302 |
| oren_obc | 0.162866 | 0.164018 | 0.162520 | 0.168625 |

Output checksum (stdout): `199990000`
