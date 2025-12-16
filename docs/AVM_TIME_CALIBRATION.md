# AVM Time Calibration (Host Convenience)

AVM supports a deterministic virtual clock for consensus and nested universes:

- In deterministic mode (`AVM_DETERMINISTIC=1`), `oren_time_now_ns()` is **derived** from:
  - `AVM_TIME_START_NS` (virtual origin)
  - accumulated `oren_sleep_ms(ms)` (`+ ms * 1e6`)
  - executed “gas” count (`+ gas_executed * AVM_TIME_STEP_NS`)

This is a *logical clock*. It is **not** intended to match the host wall clock.

## What `AVM_TIME_STEP_NS` means

`AVM_TIME_STEP_NS` is:

- “virtual nanoseconds per gas unit”

It is **not**:

- “nanoseconds of CPU time per instruction”
- “cycles”
- “a real-time guarantee”

Consensus semantics depend on **gas** being deterministic and semantic. `AVM_TIME_STEP_NS` is just a scale factor mapping gas units into a monotonic virtual time value.

## Why calibrate it anyway?

Sometimes you want virtual timeouts/backoffs to “feel” roughly like real time on your development machine (especially when you haven’t stabilized gas costs or implemented more realistic domain costs yet).

For that, you can measure how many gas units per second your host executes and pick a convenient `AVM_TIME_STEP_NS`.

## macOS benchmark script

This repo includes a small “pure compute” benchmark that:

- runs an infinite loop (stopped safely by `AVM_GAS=...`)
- measures host wall elapsed time
- reports `ns_per_gas` and suggests `AVM_TIME_STEP_NS`

Run:

```sh
bash tools/bench/bench_time_scale.sh
```

Or override the benchmark gas budget:

```sh
AVM_GAS_BENCH=200000000 bash tools/bench/bench_time_scale.sh
```

The script prints a JSON line from:

- `./avm --print-run-json build/bench_gas.obc`

and computes:

- `ns_per_gas = wall_elapsed_ns / gas_executed`

## Important limitations

- The benchmark result is **host- and build-dependent** (CPU, OS, compiler flags, etc.).
- This does **not** make deterministic virtual time “more correct”; it only makes it more intuitive for interactive use.
- For consensus jobs, treat virtual time as a *simulation time* derived from work, not as a wall-clock substitute.

