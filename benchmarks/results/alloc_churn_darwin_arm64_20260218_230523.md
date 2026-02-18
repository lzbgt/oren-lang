# alloc_churn benchmark (20260218_230523)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 3c43d9fa5b0caf158aab2dd2261126ce95847a72
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.004454 | 0.004448 | 0.003909 | 0.005357 |
| oren_c | 0.115359 | 0.115205 | 0.112578 | 0.116936 |
| oren_native | 0.606772 | 0.611050 | 0.604807 | 0.628708 |
| oren_obc | 0.400304 | 0.399731 | 0.398566 | 0.400659 |

## RSS (bytes)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 1294336 | 1294336 | 1294336 | 1294336 |
| oren_c | 68632576 | 68652236 | 68616192 | 68698112 |
| oren_native | 53805056 | 53805056 | 53805056 | 53805056 |
| oren_obc | 61358080 | 61364633 | 61358080 | 61390848 |

Output checksum (stdout): `199990000`
