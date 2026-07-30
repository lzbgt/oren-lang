# Native IR and LLVM Backend Plan

Date: 2026-07-30

## Decision

Oren should not replace the current x64 and ARM64 native emitters with LLVM in
one refactor. The durable path is to formalize a backend-neutral native IR first,
then add LLVM as an optional native backend consumer once parity gates prove the
contract.

This keeps the existing native emitters as the correctness oracle while making
future optimization, portability, and debug tooling easier.

## Current Facts

- Current native lowering is already split across shared semantic/runtime layers
  and architecture-specific emitters:
  - Shared: `native_ops_v0.oren`, `native_toplevel.oren`,
    `native_callable.oren`, `native_runtime_inject.oren`,
    `native_runtime_obj_cache*.oren`, and `native_stat_abi.oren`.
  - x64: `x64_native_program.oren` plus `x64_native_program/*`.
  - ARM64: `arm64_native_program.oren`, `arm64_native_expr*.oren`,
    `arm64_native_stmt*.oren`, and `arm64_native_program/*`.
- Current native emitters encode non-trivial Oren semantics that LLVM will not
  infer automatically: tagged values, runtime helper ABI, GC/tracking roots,
  safepoints, call-depth hooks, panic/error routing, runtime-object caching,
  debug sidecars, and per-platform syscall/ABI behavior.
- Local toolchain evidence on this host: `/usr/bin/clang` is present
  (`Apple clang version 21.0.0`), while `llvm-config` and `llc` are not on
  `PATH`. LLVM enablement must therefore use explicit toolchain detection and
  skip/fail clearly when the full LLVM toolchain is absent.

## Native IR v0 Contract

The first implementation target is a small serialized IR after current semantic
lowering and before architecture-specific instruction emission.

Required module state:

- Target triple or platform descriptor.
- Runtime profile and injected-runtime requirements.
- Data blobs, C strings, globals, debug roots, and exported/imported symbols.
- Function table with stable names, arity, local frame requirements, and source
  location metadata.

Required function state:

- Basic blocks with stable labels and explicit terminators.
- Value operations for tagged i64 values, raw pointers, booleans, floats, and
  byte-buffer/string pointers.
- Runtime helper calls with explicit ABI surface: args, result, clobbers,
  safepoint flag, and call-depth behavior.
- GC-visible roots and safepoint spill surfaces as explicit IR records.
- Panic/error exits, branch conditions, and source-token diagnostics.
- Platform ABI annotations for SysV, Win64, and AAPCS where the current runtime
  ABI requires fixed registers or stack layout.

Non-goals for v0:

- Do not replace x64/ARM64 emitters.
- Do not infer GC roots from LLVM analysis.
- Do not make LLVM the default native backend.
- Do not depend on LLVM libraries being present on every developer host.

## LLVM Backend Shape

LLVM should be introduced behind an explicit backend flag such as
`--backend llvm-native` once the native IR dumper and parity fixtures exist.

Initial LLVM lowering should be deliberately narrow:

- Emit textual LLVM IR or object output through a detected LLVM toolchain.
- Start with `examples/hello.oren`, scalar integer arithmetic, direct calls, and
  simple global strings.
- Route allocation, string, list, panic, and syscall behavior through the same
  native runtime helper ABI used by current native backends.
- Preserve explicit safepoint/root metadata from native IR instead of relying on
  optimizer reconstruction.

The LLVM backend graduates only after it passes parity against bytecode, C, and
the existing native emitters for the selected fixture tier.

## Verification Gates

Initial gates:

- `make verify-native-ir-dump` runs `oren dump native-ir examples/hello.oren`
  and checks the JSON schema, x64-linux target ABI, validator status, linked
  function names, and `main` entry block skeleton.
- `make verify-native-ir-validator` runs the v0 structural validator fixture
  across bytecode and native backends, covering unterminated blocks, duplicate
  functions, unknown branch targets, missing safepoint root records, and
  platform ABI mismatch.
- Cross-backend parity for a small fixture set: hello, integer arithmetic,
  direct function calls, string concat, list length/get, panic path, and one
  runtime helper call.
- `make verify-native-ir-toolchain` reports `clang`, `llvm-config`, and `llc`
  availability without assuming they exist. It writes
  `build/native_ir/toolchain.txt` and only requires a complete LLVM toolchain
  when `NATIVE_IR_REQUIRE_LLVM=1`.

Graduation gates:

- `make stage2`
- `make test-native-quick`
- `make verify-native-x64-compile`
- `make test-avm`
- `make verify-libavm-ios`
- Full `make test`
- Dedicated Arch x64 committed-source smoke on `bruce@192.168.0.102`

## Migration Boundary

The native IR is allowed to become the shared source for future codegen, but only
after it has round-trip/parity evidence. Until then:

- x64 and ARM64 emitters remain production paths.
- LLVM remains opt-in.
- Runtime-object cache keys must include backend identity and native-IR version.
- Any optimization pass must preserve Oren observable semantics before it is
  enabled by default.

## Immediate Next Work

1. Done: add a `NATIVE-IR-LLVM` tracked task.
2. Done: add `make verify-native-ir-toolchain`, a detect-only LLVM toolchain
   probe that records local `clang`, `llvm-config`, and `llc` availability.
3. Done: add `lib/compiler/native_ir_v0.oren`, a native-IR v0 schema/validator
   module with no production backend switch.
4. Done: add `oren dump native-ir` plus `make verify-native-ir-dump` for
   `examples/hello.oren`.
5. Add parity fixtures before emitting LLVM object code.
