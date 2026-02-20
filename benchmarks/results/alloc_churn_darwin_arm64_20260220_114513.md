# alloc_churn benchmark (20260220_114513)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: d7fd4083eec6f78324207a68acc84f65abe638e9
- runs: 1 (warmups: 0)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.002830 | 0.002830 | 0.002830 | 0.002830 |
| oren_c | 0.030797 | 0.030797 | 0.030797 | 0.030797 |
| oren_native | 0.360994 | 0.360994 | 0.360994 | 0.360994 |
| oren_obc | 0.163800 | 0.163800 | 0.163800 | 0.163800 |

## Arena trace (median counts)

| variant | allocs | alloc_bytes | spills | spill_bytes | push | pop | epoch_reset | mmap_fail |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| oren_native | 40000 | 1600000 | 0 | 0 | 1 | 1 | 1 | 0 |

Output checksum (stdout): `199990000`
