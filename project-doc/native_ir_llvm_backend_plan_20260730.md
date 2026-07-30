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
    `oren test --backend llvm-native` until executable runtime/helper parity
    exists.
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
18. Done: add first LLVM linked-execution parity fixture. `make
    verify-native-ir-llvm-runtime` builds
    `tests/fixtures/native_ir_llvm_runtime_main.oren` with the native backend as
    oracle, builds the same fixture with `--backend llvm-native`, links the LLVM
    relocatable object into a tiny C harness, and runs it on host ARM64 macOS.
    The fixture stays inside the current semantic subset and proves CFG, local
    slots, comparisons, and arithmetic execute after LLVM object linking.
19. Done: add helper-bearing LLVM linked-execution parity. The lowerer now
    forwards runtime-helper `argc` plus four argument slots into
    `oren_llvm_runtime_helper`, and `make verify-native-ir-llvm-helper-runtime`
    builds `tests/fixtures/x64_print_main.oren` with the native backend as
    oracle, builds the LLVM object, links it against a tiny helper shim, and
    proves helper invocation plus printed output on host ARM64 macOS.
20. Done: replace the print helper shim with generated LLVM helper semantics
    for the constant-string print subset. The lowerer maps `print` helper calls
    to `oren_llvm_helper_print`, now emits descriptor-backed string globals, and calls libc
    `puts`; `make verify-native-ir-llvm-helper-runtime` now links only a tiny
    harness that invokes `oren_native_ir_main_probe`, so printed-output parity
    must come from generated LLVM IR.
21. Done: add generated LLVM `exit` helper semantics. The lowerer maps `exit`
    helper calls to `oren_llvm_helper_exit`, truncates the current raw `i64`
    code to `i32`, calls libc `exit`, and `make
    verify-native-ir-llvm-exit-runtime` compares the LLVM-linked process exit
    status against the native backend oracle.
22. Done: replace the token-id generic helper dispatcher with deterministic
    named helper symbols for unresolved `oren_*` runtime helpers. The LLVM
    lowerer now emits declarations and calls such as
    `oren_llvm_helper_oren_string_eq(argc,arg0,arg1,arg2,arg3)`, preserving the
    explicit native-IR argument count while giving future runtime linking a
    stable per-helper symbol surface.
23. Done: implement the first real named `oren_*` helper body. The lowerer maps
    `oren_string_len` to generated `oren_llvm_helper_oren_string_len`; it now
    loads UTF-8 byte length from `%oren_llvm_string` descriptors, and `make
    verify-native-ir-llvm-string-runtime` proves linked execution parity against
    the native backend oracle.
24. Done: add descriptor-backed string equality semantics. `oren_string_eq`
    lowers to generated `oren_llvm_helper_oren_string_eq`, compares descriptor
    lengths plus bytes with `memcmp`, and `make
    verify-native-ir-llvm-string-eq-runtime` proves equal and unequal string
    branches execute against the native backend oracle.
25. Done: add constant-token string slice materialization. `oren_string_slice`
    originally lowered through synthesized string-token IDs, and `make
    verify-native-ir-llvm-string-slice-runtime` proved composition through
    generated equality/length helpers against the native backend oracle.
26. Done: add constant-token byte and char access helpers. The lowerer emits
    generated `oren_llvm_helper_oren_string_byte_at_unchecked`,
    `oren_llvm_helper_oren_string_char_at`, and
    `oren_llvm_helper_oren_string_char_at_unchecked` switch bodies; `make
    verify-native-ir-llvm-string-access-runtime` proves unchecked byte values and
    checked/unchecked char-token results compose with generated string equality.
27. Done: add conservative local-constant propagation for generated helper
    tables. A local is constant only when it has a single constant-propagatable
    assignment, so string slice/access helpers now support source/index/range
    arguments that flow through locals without guessing across reassignment or
    branch merges.
28. Done: replace LLVM string-token switch helpers with descriptor handles.
    String constants lower to descriptor globals, `print`/`len`/`eq`/`byte_at`
    load descriptor fields directly, `eq` uses byte-length plus `memcmp`, and
    `slice`/known-string `+` allocate descriptor-backed strings. The existing
    slice runtime gate compares an allocator-backed slice against an
    allocator-backed concat result, proving true runtime helper arguments without
    adding another broad test.
29. Done: add the LLVM string runtime allocation seam and ownership metadata.
    `%oren_llvm_string` is now `{ len, data, owner_kind }`; static descriptors
    use `owner_kind=0`, heap strings use `owner_kind=1`, and `slice`/concat call
    generated `oren_llvm_runtime_alloc_string(len)` instead of embedding direct
    descriptor allocation logic in each helper.
30. Done: remove temporary libc allocation from lowered LLVM program objects.
    `oren_llvm_runtime_alloc_string(len)` now calls external
    `oren_llvm_runtime_alloc_bytes(bytes, kind)` and
    `oren_llvm_runtime_register_string(desc, data, len)` hooks.
31. Done: move those hooks into the real C runtime surface. The hook
    implementation lives in `lib/runtime/070_llvm_native_hooks.inc`, registers
    string bytes as GC-tracked string storage, registers descriptor blocks as
    tracked runtime structs, and validates `{ len, data, owner_kind=1 }`
    metadata. The focused LLVM string runtime probes now link `lib/runtime.c`
    plus `lib/runtime_buf.c` instead of a harness-only shim.
32. Done: lower native-IR helper root metadata into LLVM/runtime root hooks.
    Safepoint helper calls now emit `oren_llvm_runtime_roots_mark`,
    `oren_llvm_runtime_roots_push_string`, and
    `oren_llvm_runtime_roots_reset`; the C runtime keeps a v0 descriptor-root
    stack, marks live descriptor/data allocations during GC, and treats
    non-descriptor tagged immediates as no-op roots.
33. Done: add forced GC-at-safepoint parity for generated helper calls.
    Lowered helper sites call `oren_llvm_runtime_safepoint_poll()` while
    descriptor roots are active; focused string slice/access runtime gates run
    with `OREN_LLVM_FORCE_GC_AT_SAFEPOINT=1` and assert the forced collection
    counter, root-stack reset, and output parity.
34. Done: extend descriptor-aware lowering to non-constant string concat inputs.
    The LLVM lowerer now tracks proven descriptor values through string
    constants, string helper results, single-assignment locals, and concat
    results; `+` lowers to `oren_llvm_helper_oren_string_concat` whenever both
    operands are proven descriptors, not only when both are compile-time string
    literals. The slice runtime fixture now checks `slice_result + suffix`,
    exercising a heap descriptor input under forced GC-at-safepoint.
35. Done: add adjacent descriptor-backed string helper coverage without another
    broad gate. `oren_string_slice_unchecked` now lowers to a named generated
    helper that reuses the descriptor-backed slice implementation, and
    `oren_string_char_code_at` lowers through the descriptor byte-access body;
    the existing slice/access runtime parity gates prove both under real runtime
    allocation hooks, safepoint root handling, and forced GC-at-safepoint.
36. Done: extend descriptor ABI input coverage beyond single-assignment local
    dataflow. The LLVM lowerer now runs a conservative native-IR CFG must
    analysis for descriptor locals, intersects predecessor facts at joins, uses
    those facts for descriptor concat selection, and pushes currently proven
    descriptor locals as safepoint roots. The slice runtime fixture now proves
    `picked + suffix` after an `if` join under forced GC-at-safepoint.
37. Done: add the first native-IR/LLVM container layout record. Array literals
    now lower to `%oren_llvm_list { len, data, owner_kind }` descriptors,
    descriptor-backed `index_get` lowers to `oren_llvm_helper_oren_list_get`,
    and the real C runtime validates registered list descriptor metadata. `make
    verify-native-ir-llvm-list-runtime` proves linked execution parity against
    the native backend oracle without falling back to opaque array/index calls.
38. Done: extend LLVM list descriptors to mutation plus GC root marking for
    list descriptors. Proven list `index_set` now lowers to
    `oren_llvm_helper_oren_list_set`, helper safepoints push proven list locals
    through `oren_llvm_runtime_roots_push_list`, and the real C runtime marks
    rooted LLVM list descriptors plus backing storage during forced GC. `make
    verify-native-ir-llvm-list-runtime` now forces GC between list allocation
    and later reads, verifies mutation through an alias, and rejects opaque
    array/index get/set fallbacks for this subset.
39. Done: extend list descriptors to push/growth and broader runtime-varying
    helper arguments. `%oren_llvm_list` now carries `{ len, data, owner_kind,
    capacity }`; array literals allocate with `len=capacity`, optimized
    `oren_new_list_int(capacity)` allocates with `len=0`, and proven list
    `oren_list_int_push*`/`oren_list_push*`, `oren_list_int_len*`/`oren_list_len*`,
    and `oren_list_int_get*`/`oren_list_get*` calls normalize to descriptor
    push/length/get helpers. `make verify-native-ir-llvm-list-runtime` proves
    empty-list growth through repeated push, length reads, indexed reads, alias
    mutation, and forced-GC list rooting.
40. Done: add runtime-level nested descriptor root marking. The C runtime now
    recursively marks LLVM list descriptor contents, including nested list and
    string descriptors, with a bounded recursion guard. `make
    verify-native-ir-llvm-list-runtime` builds a parent-list -> child-list ->
    dynamic-string graph, pushes only the parent list root, forces a safepoint
    GC, and proves the nested descriptors remain live.
41. Done: add lowerer-side element descriptor provenance for nested list
    indexing. The LLVM lowerer now carries string/list descriptor facts through
    list origins, local aliases, constant-index list reads, and list-helper get
    calls; explicit helper roots are routed by proven descriptor kind instead of
    treating every tagged root as a string. The list runtime fixture now proves
    `parent[0][0] + "ed"` lowers to descriptor list gets plus descriptor string
    concat after forced GC.
42. Done: broaden descriptor ABI lowering to bytes. LLVM-native now has
    `%oren_llvm_bytes { len, data, owner_kind }`, runtime-owned raw byte
    allocation plus registration hooks, type-specific bytes roots, and generated
    descriptor helpers for `oren_bytes_from_hex`, `oren_bytes_len`, and
    `oren_bytes_get_u8`. `make verify-native-ir-llvm-bytes-runtime` proves
    linked execution parity against the native backend oracle while forcing GC at
    helper safepoints.
43. Done: expand bytes descriptor materialization and interop helpers.
    `oren_bytes_to_hex` now returns a descriptor-backed string,
    `oren_bytes_unpack` returns a descriptor-backed list, and
    `oren_bytes_pack` validates list elements before allocating a runtime-owned
    bytes descriptor. The focused bytes runtime gate proves hex -> bytes ->
    list -> mutated bytes -> hex roundtrip under forced GC-at-safepoint.
44. Done: split the public LLVM lowerer entrypoint from its implementation before
    adding more helper families. `scripts/native_ir_llvm_lower.py` is now a
    stable CLI wrapper, while `scripts/native_ir_llvm_lower_impl.py` carries the
    current implementation below the source-line cap.
45. Extend bytes descriptors to endian read/write helpers, byte slices/copy, and
    runtime-varying inputs, then extend non-string descriptor coverage to maps
    and runtime-shaped records.
