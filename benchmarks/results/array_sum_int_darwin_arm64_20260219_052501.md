# array_sum_int benchmark (20260219_052501)

## Host

- host: Bruce-Mac
- platform: macOS-26.2-arm64-arm-64bit-Mach-O
- machine: arm64
- cpu: Apple M2 Pro
- cpu_cores: 10
- mem_bytes: 17179869184
- git_rev: 1cf040b7b662a7f9f986c450901ed2c321741a9f
- runs: 5 (warmups: 1)

## Results (seconds)

| variant | median | mean | min | max |
| --- | --- | --- | --- | --- |
| c | 0.003905 | 0.003947 | 0.003710 | 0.004354 |
| oren_c | 0.083507 | 0.083608 | 0.082406 | 0.084458 |
| oren_native | 0.104486 | 0.104512 | 0.104336 | 0.104687 |
| oren_obc | 0.626739 | 0.627143 | 0.623585 | 0.631583 |

Output checksum (stdout): `999000000`
