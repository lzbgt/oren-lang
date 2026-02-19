# multi_list_sum benchmark (20260219_113021)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: bcb4bd9c7ae6c8dd7c3fd630d9551bc27c91ce4f
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.009779 | 0.009907 | 0.009566 | 0.010621 |
| oren_c | 0.028961 | 0.029156 | 0.028088 | 0.030435 |
| oren_native | 0.032866 | 0.032747 | 0.032151 | 0.033138 |
| oren_obc | 1.236973 | 1.242593 | 1.228680 | 1.261348 |

Output checksum (stdout): `2995000000`
