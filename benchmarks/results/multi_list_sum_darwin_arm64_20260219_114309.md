# multi_list_sum benchmark (20260219_114309)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: f3512bcebbca24e173d701cd87abb9162c1a77e6
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.008527 | 0.008550 | 0.008341 | 0.008773 |
| oren_c | 0.026208 | 0.026168 | 0.025645 | 0.026670 |
| oren_native | 0.031299 | 0.031610 | 0.031071 | 0.032289 |
| oren_obc | 0.783350 | 0.783793 | 0.779768 | 0.790275 |

Output checksum (stdout): `2995000000`
