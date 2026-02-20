# alloc_churn benchmark (20260220_083057)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: b2f3277628a3c730a5a25ccd7e202297ec793c66
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| oren_native | 4.896915 | 4.896915 | 4.896915 | 4.896915 |

Output checksum (stdout): `[gc_reuse] tries=10001 hits=3 misses=10001 hit_bytes=9216
[gc_reuse] tries=9989 hits=4990 misses=5001 hit_bytes=5115904
[gc_reuse] tries=9989 hits=4986 misses=5006 hit_bytes=5111808
[gc_reuse] tries=9989 hits=4987 misses=5005 hit_bytes=5112832
199990000`
