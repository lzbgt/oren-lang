# alloc_drop benchmark (20260220_081737)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: a35b6e4221732f305400f671c01d4f11b2b3bcb3
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| oren_native | 12.134971 | 12.134971 | 12.134971 | 12.134971 |

Output checksum (stdout): `[gc_reuse] tries=5719 hits=3 misses=5719 hit_bytes=480
[gc_reuse] tries=6318 hits=1420 misses=4900 hit_bytes=91232
[gc_reuse] tries=6381 hits=1569 misses=4815 hit_bytes=100800
[gc_reuse] tries=6394 hits=1597 misses=4800 hit_bytes=102480
[gc_reuse] tries=6393 hits=1599 misses=4798 hit_bytes=102720
[gc_reuse] tries=6389 hits=1588 misses=4804 hit_bytes=102016
alloc_drop keep=11`
