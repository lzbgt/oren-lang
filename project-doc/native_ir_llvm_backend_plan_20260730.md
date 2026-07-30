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
  (`Apple clang version 21.0.0`), and Homebrew LLVM 19.1.6 is installed under
  `/opt/homebrew/opt/llvm`. The detector now finds
  `/opt/homebrew/opt/llvm/bin/llvm-config` and `/opt/homebrew/opt/llvm/bin/llc`
  even when Homebrew LLVM is not exported into `PATH`.

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
  function names, and `main` entry block operation records.
- `make verify-native-ir-validator` runs the v0 structural validator fixture
  across bytecode and native backends, covering unterminated blocks, duplicate
  functions, unknown branch targets, missing safepoint root records, and
  platform ABI mismatch.
- Cross-backend parity for a small fixture set: hello, integer arithmetic,
  direct function calls, string concat, list length/get, panic path, and one
  runtime helper call. `make verify-native-ir-parity` now checks that the
  native-IR dump preserves the exact linked function surface and emits required
  source-operation kinds, closed CFG branch/jump targets, helper-call mirrors,
  ABI-specific clobbers, call-depth mode, and tagged safepoint root records for
  that fixture set across `x64-linux`, `x64-windows`, and `arm64-macos`.
- `make verify-native-ir-toolchain` reports `clang`, `llvm-config`, and `llc`
  availability without assuming they exist on `PATH`. It honors
  `NATIVE_IR_CLANG`, `NATIVE_IR_LLVM_CONFIG`, and `NATIVE_IR_LLC`, probes common
  Homebrew LLVM prefixes, writes `build/native_ir/toolchain.txt`, and only
  requires a complete LLVM toolchain when `NATIVE_IR_REQUIRE_LLVM=1`.
- `make verify-native-ir-llvm-object` validates the native-IR input and records
  a deterministic object-emission manifest under
  `build/native_ir/llvm_object/`. On hosts without full LLVM it reports
  `status=skipped`; with `NATIVE_IR_REQUIRE_LLVM=1` it fails fast instead of
  silently accepting a missing `llvm-config`/`llc`.

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
5. Done: add linked-surface parity fixtures before emitting LLVM object code.
6. Done: add first source-operation lowering for the parity fixture set:
   constants, local get/set, binary/unary ops, calls, arrays, index get/set,
   expression results, and explicit opaque statement/expression placeholders.
7. Done: replace `If`/`While` opaque control-flow placeholders with native-IR
   CFG blocks, branches, jumps, and fallthrough continuations.
8. Done: add explicit runtime-helper ABI and safepoint/root records for
   runtime builtin calls (`print`, `exit`, and `oren_*`) before emitting LLVM
   object code.
9. Done: add opt-in LLVM object-emission scaffolding. The gate validates
   native IR, writes an emission manifest, skips clearly on this host because
   `llvm-config`/`llc` are absent, and fails fast when
   `NATIVE_IR_REQUIRE_LLVM=1`.
10. Done: add backend-neutral type/layout records for values, helper arguments,
    and returns before attempting semantic LLVM IR lowering beyond the probe
    object. The v0 schema now carries `tagged`/`void` layouts, function
    return/value-type records, and runtime-helper arg/result type records; dump,
    parity, validator, and LLVM-object gates validate that surface.
11. Done: add semantic LLVM IR lowering for the typed const/CFG/helper subset
    behind the existing object gate. The gate now writes textual LLVM IR with
    real `main` CFG blocks, branches, i64 local slots, constants,
    arithmetic/comparison ops, opaque shims for not-yet-semantic calls and
    container operations, and runtime-helper call markers before either skipping
    object emission on hosts without full LLVM or passing the IR to `llc`.
12. Done: add `verify-native-ir-llvm-lowering`, a textual lowering parity gate
    over the same seven native-IR fixtures and three target platforms as the
    linked-surface parity gate. This proves the current LLVM textual lowering
    remains target-triple aware and fixture-broad even on hosts without `llc`.
13. Done: extract textual LLVM lowering into reusable
    `scripts/native_ir_llvm_lower.py` so the object gate and future opt-in
    backend path consume the same validated native-IR lowering implementation
    instead of verifier-local heredoc code.
14. Done: detect the installed Homebrew LLVM toolchain even when it is not on
    `PATH`; `NATIVE_IR_REQUIRE_LLVM=1 make verify-native-ir-llvm-object` now
    emits `build/native_ir/llvm_object/probe.o` on this host.
15. Done: add an opt-in compile-only `llvm-native` backend command path.
    `oren build --backend llvm-native` now delegates through the validated native
    IR dump, reusable textual LLVM lowerer, and full-toolchain `llc` emission to
    produce relocatable objects plus adjacent native-IR/LLVM/manifest sidecars.
    `make verify-native-ir-llvm-backend` proves helper-bearing hello object
    emission, helper-free arithmetic object emission, and explicit rejection of
    `oren test --backend llvm-native` until object linking/runtime parity exists.
16. Done: add `make verify-native-ir-llvm-workflow`, a timed aggregate local
    verification path for native-IR/LLVM work. It runs the focused native-IR
    gates, stage2, native quick, x64 compile, AVM, and iOS SDK gates while
    intentionally omitting a trailing `make test` duplicate because `make test`
    currently aliases `test-native-quick`.
17. Done: add `make verify-native-ir-llvm-smoke`, the default fast iteration
    gate for native-IR/LLVM command-path work. It uses two integration programs
    (`examples/hello.oren` and `tests/fixtures/x64_div_mod_main.oren`) to cover
    toolchain discovery, build dispatch, native-IR dump, LLVM lowering, `llc`
    object emission, helper calls, helper-free arithmetic, target triples, and
    compile-only `test` rejection without replaying broad runtime suites.
18. Add LLVM runtime linking/execution parity fixtures; keep x64/ARM64 as the
    oracle until the LLVM path can run parity programs, not just compile
    relocatable objects.
