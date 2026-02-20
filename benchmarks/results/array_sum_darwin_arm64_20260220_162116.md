# array_sum benchmark (20260220_162116)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 54bd38a49b4173153227102c4117f528312ffaae
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003955 | 0.003927 | 0.003815 | 0.004036 |
| oren_c | 0.008499 | 0.008452 | 0.008136 | 0.008616 |
| oren_native | 0.015726 | 0.015782 | 0.015576 | 0.016037 |
| oren_obc | 0.143175 | 0.142979 | 0.142196 | 0.143473 |

Output checksum (stdout): `999000000`
