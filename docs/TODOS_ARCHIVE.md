# Archived TODOs

This file preserves the previous long-form rolling TODO list (history + detailed status).

- Archived on: 2025-12-18
- Current prioritized TODOs live in: `docs/TODOS.md`

## Archived (2025-12-21) — Unify `struct` semantics (map-shaped, mutable) across backends

- Decision: in rolling v0, `struct` values are **map-shaped** (string-keyed) across **C + AVM bytecode + native** backends.
  - `x.field` lowers to `x["field"]` semantics (map key lookup).
  - `x.field = v` mutates the field (map key set).
  - Layout-stable use-cases remain `@pack` (byte views) and `@abi` (layout-only), not v0 structs.
- Compiler/linker: removed the global “field name → index must match across all types” constraint (was a v0 hack for positional struct layouts).
- Bytecode backend:
  - type constructors emit `NEW_MAP` with string keys (not `NEW_LIST`)
  - member read/write compile to `GET_INDEX`/`SET_INDEX` with string keys
- Native backend:
  - type constructors now build maps via `oren_new_map` + `oren_map_set` (no raw `oren_alloc_struct` field buffers)
  - member reads use `oren_map_get` (no field-offset fast path in v0)
- Tests:
  - added `tests/avm/test_struct_member_set.oren`
  - added `tests/native/test_struct_member_set.oren`
- Verified: `make test` on macOS passes.

## Archived (2025-12-21) — AVM snapshot v7: scheduler pause/resume

- AVM snapshots: added **AVMSNAP7** with full scheduler snapshot/restore (tasks + channels + ready/select queues).
  - `--snapshot-out` now works even when `spawn`/channels are active (pause/resume of non-trivial scheduler).
  - Updated AVM test from “forbidden” to “resume” (`tests/avm/test_snapshot_tasks_resume.oren`) and oretest wiring.
- Internal refactor: moved scheduler structs (`AvmTask`, `AvmChan`, `AvmSched`) into `lib/avm/avm_internal.h` so snapshot code can serialize them.
- Bytecode backend fix: `oren_yield()` now returns a canonical `nil` value (stack-balanced as an expression), preventing verifier stack-height mismatches in real programs.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-21) — Allocator control for large typed buffers (HPC)

- Implemented env-configurable allocation policy for large numeric payloads (bootstrap-friendly, rolling):
  - `OREN_RAW_MMAP_THRESHOLD` (0 disables) for raw typed-buffer payload mmap threshold (C + native).
  - `OREN_BUF_ALIGN=8|16|32|64` (default 64) for typed-buffer alignment (NEON/cacheline-friendly).
  - `OREN_BUF_FORCE_MMAP=1` (native) to force typed buffers to mmap (debug/benchmark).
  - `OREN_BUF_PAYLOAD_LIMIT_BYTES` to bound payload size deterministically and fail with a budget error.
- Test runner hardening:
  - `cmd/oretest` sanitizes allocator env vars (prevents user shell env from changing test behavior).
- Tests:
  - Added churn-style fragmentation stress: `tests/modules/test_buffer_alloc_stress.oren`.
  - Added payload-budget regression: `tests/modules/test_buffer_payload_limit.oren`.
- Verified: `make test` on macOS passes.

## Archived (2025-12-21) — Compiler-in-AVM v1 (VirtualFS + argv-as-data)

- Extended AVM nested-universe interface `avm.run_obc_bytes` (Domain 8, op 0):
  - Accepts `cfg["argv"]` as `LIST<string>` and injects it into the child VM (`argc/argv`).
  - Returns `vfs_snapshot` as AVMVFS01 bytes so the parent can read files produced in the child’s VirtualFS.
- Added integration harness `tests/avm/fixtures/compiler_in_avm_vfs_harness.oren`:
  - Runs the compiler `.obc` in a nested universe with VirtualFS fixtures (no host effects).
  - Extracts `out.obc` from returned `vfs_snapshot` and runs it in another nested universe.
- Wired into `./oretest --full` as fixture `compiler_in_avm_smoke` (host FS read restricted to `build/` only).
- Verified: `./oretest --full --target macos` passes.

## Archived (2025-12-21) — Typed buffer slice/strided views + iteration semantics

- Standardized portable view encodings in `std/buffer`:
  - slice view: `[buf, off, len]`
  - strided view: `[buf, off, len, stride]`
  - matrix view (existing): `[buf, off, rows, cols, row_stride]`
- Added view helpers:
  - `buffer.slice_slice(...)` (slice-of-slice)
  - `buffer.strided_new(...)` plus load/store helpers per element kind
- Made `for x in view` iterate *values*, not metadata, by teaching `oren_iter_next` to recognize these view lists:
  - C runtime: `lib/runtime.c`
  - AVM runtime: `lib/avm/avm_native.inc`
  - Native runtime: `lib/runtime_native.oren`
- Extended integration coverage in `tests/modules/test_buffer_views.oren`:
  - slice, slice-of-slice, strided view, `for-in` over views
  - `std/linalg` view helpers (`dot_*_view`) and strided matrix-view matmul (`matmul_f32_mat_view`)
- Verified: `./oretest --target macos` and `./oretest --full --target macos` pass.

## Archived (2025-12-19) — Previously in `docs/TODOS.md` “Recently Completed”

- Native backend spawn intrinsic: removed remaining hardcoded `svc #0`/`svc #0x80` + numeric syscall IDs; now uses `arm64_abi_{macos,linux}.oren` tables.
- Mach-O minimal exit stub (`macho_emit_exit_arm64`): now uses `arm64_abi_macos.oren` syscall ABI constants (no embedded MOVK/SVC magic).
- FS mounts semantics hardened: longest-prefix + boundary checks in native runtime; AVM host mounts match (incl. host-path allow-as-is under enrolled host prefixes); added overlapping-mount regression tests.
- FS allow-prefix policy hardened: require boundary when a prefix does not end with `/` (prevents `build` matching `build2`); applied to native capsule + AVM host allow-prefix checks.
- ABI tables expanded: centralized NET-related syscalls (socket/connect/bind/listen/accept/sendto/recvfrom) and other process/syscall staples (execve/wait4/kill/gettimeofday/fcntl, sockopt/shutdown, peer/sockname) for macOS+Linux; removed more numeric `sysno=` literals from syscall lowering.
- Native string propagation: fixed `+` stringiness to require both operands, added `oren_list_get` string propagation and array-of-strings list inference; added `tests/native/test_string_list_eq.oren`.
- ABI constants: moved remaining Darwin `kevent` syscall number and Linux `AT_*` syscall-arg flags (AT_SYMLINK_NOFOLLOW/AT_REMOVEDIR) into repo-owned ABI tables; removed the last hardcoded `sysno=363` from syscall lowering.
- ABI constants: centralized Linux `AT_FDCWD=-100` into `arm64_abi_linux.oren` and added a signed-immediate loader helper (removes remaining `MOVN imm=99` magic from syscall lowering).
- Native string comparisons: added regression coverage for `string == nil` / `nil == string` (must not lower to `strcmp`).
- Mach-O emitter: replaced key numeric header/load-command/bind-opcode literals with repo-owned named constants (keeps ABI knowledge local without SDK headers).
- Mach-O emitter: removed remaining layout magic numbers (segment alignment, codesign page size, exit-stub header sizing, section flags) by centralizing them as named constants.
- Mach-O emitter: replaced raw segname/sectname byte sequences with a fixed-16 string helper (less brittle, clearer).
- Mach-O emitter: centralized remaining structural constants (prot flags, build-version packing, codesign lengths) and removed more remaining magic numbers.
- Refs: vendored Mach-O headers (`loader.h`, `nlist.h`) into `docs/refs/macho/` pinned to an Apple OSS `cctools` commit for audit-only reference (no build dependency).
- Refs: refreshed vendored Linux/Darwin syscall references under `docs/refs/` and recorded pinned upstream commits in `docs/refs/SOURCES.md` (audit-only).
- Native backend docs: corrected `+` string concatenation note to match native lowering (`oren_add`) and current test coverage.

## Archived (2025-12-20) — Doc alignment + tracker cleanup

- Tracker: clarified docs-only verification scope to include `README.md` + `LICENSE`; reweighted TODO list to focus on attribute-driven serde as the next major language ergonomics step.
- Docs: added `docs/ATTRIBUTES.md` as the attribute cookbook and documented the emitted metadata shape.
- Docs: updated `docs/LANGUAGE_SPEC.md` to reflect current type-annotation semantics (value-level casts + `bool` normalization + `f32` rounding) and to mark `i128/u128` as ABI/layout-only until runtime semantics stabilize.
- Docs: updated `docs/SELF_HOSTING.md` to match the current multi-backend reality and to defer to `docs/BUILD_AND_VERIFY.md` for the authoritative bootstrap steps.
- Docs: updated `docs/STDLIB_LAYERS.md` to point at the refactored parser modules and to document strict attribute mode flags.

## Archived (2025-12-20) — Casting model + type plan + linalg foundation

- Casting: removed strict-casts mode (language semantics are deterministic by default).
- Casting: compiler lowers builtin cast sugar (`u8(x)`, `i32(x)`, `f32(x)`, `bool(x)`, endian spellings like `u16be(x)`) into deterministic rewrites (no dynamic call overhead).
- Casting: added `lib/std/casts.oren` as an optional clarity layer matching annotation lowering.
- Tests: added regression module test `tests/modules/test_cast_sugar.oren` and wired it into `cmd/oretest`.
- Docs: added `docs/TYPE_SYSTEM_PLAN.md` to guide gradual typing → generics/traits.
- Stdlib: added `lib/std/linalg.oren` (scalar-first `dot_*`, `axpy_*`, `matmul_*`) with module test `tests/modules/test_linalg.oren` and oretest wiring.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — Numeric cast semantics (float→int truncation)

- Casting: defined and implemented float→int cast semantics: truncate toward zero, then wrap/truncate to target width.
  - Added `oren_trunc_int` intrinsic (C runtime + AVM native + native backend inline).
  - Updated cast sugar lowering to apply `oren_trunc_int` before integer masks and to allow `f32(int)` via `x + 0.0` coercion.
- Typecheck v0: relaxed numeric cast rules so `u8(1.0)` is valid; string/bool/nil remain rejected for numeric casts.
- Tests: expanded `tests/modules/test_cast_sugar.oren` to cover float→int and `f32(int)`; kept `tests/fixtures/typecheck_bad_cast.oren` rejecting `f32("...")`.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — `as` cast operator + typecheck v0 scaffolding

- Language: added `as` cast operator (`expr as u8`) desugared to builtin cast sugar.
- Language: added opt-in `--typecheck` pass to reject obvious invalid casts and mismatched annotated boundaries.
- Tests: added `tests/modules/test_as_cast.oren` and fixture `tests/fixtures/typecheck_bad_cast.oren` wired into `cmd/oretest`.

## Archived (2025-12-20) — Test system evolution spec (no rewrite)

- Documented a minimal Oren-native test manifest shape and runner CLI/output contract in `docs/TEST_SYSTEM.md`.
- The design keeps `cmd/oretest` as the current orchestrator (Go), enforcing SOLID by keeping test orchestration out of `lib/compiler/*.oren`.

## Archived (2025-12-20) — Serde JSON v1 (attribute-driven, no reflection)

- Implemented attribute-driven JSON serde helper generation (opt-in) in `lib/compiler/serde_json_lowering.oren`.
  - `@json.derive("json")` / canonical `@serde.derive("json")` on a struct triggers codegen.
  - Generates:
    - `<Type>__json_encode(x)` → JsonValue
    - `<Type>__json_decode(jv)` → `{ok, err?, v?}`
  - Supports field options:
    - `@json.rename("wire")`
    - `@json.skip()` + `@json.default(<literal>)` (skip requires default for decode determinism)
    - `@json.tag("TypeTag")` (adds `"t"` tag field, validated on decode)
- Parser: allowed `default` keyword token in attribute dotted names (`@json.default(...)`) without making `default` a general identifier.
- Tests:
  - Added `tests/modules/test_json_serde_attrs.oren` (integration: encode + decode + ordering + defaults).
  - Updated curated runner list (`cmd/oretest/main.go`) to include it.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — Serde attribute ergonomics v1 (format-first)

- Upgraded the preferred surface syntax to remove redundancy and be multi-format friendly:
  - Struct opt-in: `@serde(format="json", tag="User")` (also supports positional `@serde("json")`).
  - Field options: `@serde(rename="wire")`, `@serde(skip=true, default=0)`.
- Kept rolling back-compat:
  - `@json.*` aliases still canonicalize to `serde.*`.
  - legacy dotted: `@json.derive("json")`, `@json.tag("User")`, `@json.rename("x")`, `@json.skip()`, `@json.default(0)`.
  - previous compact: `@serde(derive="json")` still works.
- Parser: fixed keyword-arg parsing to accept keyword tokens as keys (e.g. `default=0` where `default` is tokenized as a keyword).
- Tests: strengthened `tests/modules/test_json_serde_attrs.oren` to cover both compact `@serde(...)` and legacy dotted forms.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — Serde schema metadata v1 (`oren meta`)

- Implemented a normalized serde schema under `structs[*].serde` in metadata output (deterministic, versioned).
  - Includes: `version`, `format`, optional `tag`, and normalized fields:
    - `name`, `ann_type`, `wire`, `skip`, `default`
- Added oretest coverage to ensure `oren meta` contains the serde schema for the JSON fixture.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — CBOR v1 (RFC 8949 subset) + `@serde(format="cbor")`

- Added `lib/std/cbor.oren`:
  - deterministic CBOR encode/decode for a small portable tagged representation (`CborValue`)
  - canonical map key ordering (length then bytewise) for stable bytes
- Extended serde lowering to support `@serde(format="cbor")`:
  - generates `<Type>__cbor_encode` / `<Type>__cbor_decode` (tagged value; binary encoding is via std/cbor)
- Added integration test `tests/modules/test_cbor_serde_attrs.oren` and wired it into `cmd/oretest`.
- Vendored RFC 8949 text into `docs/refs/cbor/rfc8949.txt` for audit reference.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — CBOR streaming (CBOR Sequences, RFC 8742)

- Vendored RFC 8742 text into `docs/refs/cbor/rfc8742.txt` for audit reference.
- Added streaming-friendly API in `lib/std/cbor.oren`:
  - `cbor.decode_next(bytes, pos)` for incremental parsing (one item)
  - `cbor.decode_sequence(bytes)` for whole-buffer sequences
  - `cbor.encode_sequence(items)` for emitting sequences

## Archived (2025-12-21) — Typed buffers + views + C backend ordering fix

- **Typed buffers** (C backend runtime primitives):
  - Added `OREN_TYPE_{I32,I64,F32,F64}_BUF` + `OrenBuf` header in `lib/runtime.h`.
  - Implemented buffer ops in `lib/runtime_buf.c` (alloc, load/store, fill, add/mul/scale, dot, reduce_sum; `_into` variants for out-params).
  - Linked C backend builds against both `lib/runtime.c` and `lib/runtime_buf.c` (see `lib/compiler/compiler.oren`).
  - Added `lib/std/buffer.oren` (zero-copy slice + matrix-stride views using map-based view objects in v0).
  - Added `tests/modules/test_buffer_views.oren` and wired it into `cmd/oretest`.

- **Language ergonomics / parsing**:
  - Parser: added `[]T` prefix type annotation parsing (stored as `"[]T"` string) in `lib/compiler/parser_core.oren`.
  - Parser: removed the compile-time error that blocked `obj.field = v` (struct fields are now assignable; semantics are backend-defined in rolling mode) in `lib/compiler/parser_parse.oren`.

- **Correctness fix (high impact)**:
  - C backend: fixed a semantic bug where top-level `var` initializers were hoisted ahead of other top-level statements.
    - `var` now declares a global symbol but executes its initializer in source order by lowering to an `Assign` statement in `main_body`.
    - Implemented in `lib/compiler/transpiler.oren` by changing `collect_parts()` and removing the global-initializer hoist block.

- **Quality-of-life**:
  - C runtime: `print_value_no_newline` now prints buffer values as `<i32_buf len=N>` (etc) and no longer triggers missing-switch warnings.

- Verified:
  - `./oretest` on macOS
  - `tools/oretest_linux_docker.sh` on Linux (docker arm64)

## Archived (2025-12-21) — `std/linalg` v0.2 (buffers + safe NEON) + i32 overflow hardening

- Runtime (C backend buffers):
  - Defined wrap-safe semantics for i32 `dot` / `reduce_sum` by accumulating modulo 2^64 (avoids signed overflow UB).
  - Added arm64 NEON fast paths for i32 `dot` / `reduce_sum` (little-endian only; deterministic).
  - Added AXPY intrinsics:
    - `oren_buf_axpy_f32_{into,in_place}` (per-element float32 mul+add; avoids fused multiply-add)
    - `oren_buf_axpy_i32_{into,in_place}` (per-element wrap math)

- Stdlib:
  - `lib/std/linalg.oren` gained typed-buffer APIs (`*_buf`) and delegates to runtime buffer kernels for performance.

- Tests:
  - Extended `tests/modules/test_linalg.oren` to cover typed-buffer dot/axpy.

- Verified:
  - `./oretest` on macOS
  - `tools/oretest_linux_docker.sh` on Linux (docker arm64)

## Archived (2025-12-21) — GC allocation registry indexing (hash table) + stress test

- Runtime (C backend GC registry):
  - Replaced `oren_find_node()` linear scan over `g_allocs` with an open-addressing hash index (`g_alloc_index`) keyed by allocation pointer.
  - Kept `g_allocs` as the canonical sweep list; the index is only for O(1) lookup during mark/free.
  - Hardened explicit frees (`oren_free`, `oren_free_struct`) to remove registry nodes so the alloc registry does not grow without bound under manual frees.
  - Sweep now removes freed nodes from the index as well.

- Tests:
  - Added `tests/modules/test_alloc_gc_scale.oren` (allocation churn + periodic `oren_gc_collect()`) and wired it into `cmd/oretest`.

- Verified:
  - `./oretest` on macOS
  - `tools/oretest_linux_docker.sh` on Linux (docker arm64)
- Added tests: `tests/modules/test_cbor_sequence.oren` and wired into `cmd/oretest`.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — `std/time` v0 (UTC-only ISO8601 + epoch conversions)

- Runtime (C backend):
  - Added TIME primitives to `lib/runtime.c` / `lib/runtime.h`:
    - `oren_sleep_ns` / `oren_sleep_ms`
    - `oren_time_unix_ns`
    - `oren_time_mono_raw`
    - `oren_time_now_ns` (stable alias for stdlib + AVM parity)
- Runtime (native):
  - Added `oren_time_now_ns` alias in `lib/runtime_native.oren` (maps to unix time for now).
- Stdlib:
  - Added `lib/std/time.oren`:
    - `Duration`, `Instant`, `DateTime`
    - UTC ISO-8601 `parse_iso8601_utc` / `format_iso8601_utc`
    - `datetime_to_unix_ns` / `datetime_from_unix_ns`
    - `sleep_ms`, `now_unix_ns`, `now_ns`, `mono_raw`, `instant_now`
  - Design: UTC-only v0; fractional seconds (1..9 digits) supported; format trims trailing zeros.
- Tests:
  - Added `tests/modules/test_time_std.oren` and wired into `cmd/oretest`.
- Verified:
  - `make test` on macOS.

## Archived (2025-12-20) — `%` modulo operator (C backend + AVM + native backend)

- Language:
  - Added `%` operator tokenization + parsing with `PRODUCT_P` precedence.
  - Updated typecheck v0 category inference so `%` is int-only.
- Backends:
  - C backend lowers `a % b` to `oren_mod(a, b)` with deterministic checks (div0, i64_min%-1).
  - AVM bytecode adds opcode `MOD` (0x1F) with deterministic error semantics for div0/overflow.
  - Native backend lowers `%` to the native runtime helper `oren_mod` so semantics stay deterministic.
- Tests:
  - Added `tests/modules/test_mod.oren` and wired it into `cmd/oretest`.
- Tooling:
  - Fixed `tools/oretest_linux_docker.sh` quoting hazard by removing backticks inside docker `bash -lc` heredoc.
- Verified:
  - `./oretest --target macos`
  - `tools/oretest_linux_docker.sh`

## Archived (2025-12-21) — `oredoc openapi` (OpenAPI 3.1 export from metadata)

- Tooling:
  - Added `cmd/oredoc` (Go) to export OpenAPI 3.1 documents from `oren meta` output.
  - CLI: `./oredoc openapi <meta.json> -o out.json -title ... -version ... -format json`
  - Accepts both `-flag` and `--flag` forms for convenience.
- OpenAPI mapping (v0):
  - Exports minimal valid OpenAPI 3.1 document with `components.schemas` derived from `structs[*].serde`.
  - Maps Oren scalar annotations (`i32`, `u64`, `f32`, `bool`, `string`, `[]T`, etc.) to OpenAPI schema shapes.
- Tests:
  - Added an oretest fixture `oredoc_openapi_export` that roundtrips `oren meta` → `oredoc openapi` and validates key fields.

## Archived (2025-12-21) — C-backend build hygiene + GC stack-scan hardening

- C backend build hygiene:
  - `oren build --backend c` no longer writes generated `*.oren.c` next to sources.
  - C output is emitted alongside the output artifact (`out_path + ".c"`) and deleted on success.
- GC correctness:
  - Hardened `oren_mark_value` to validate allocation-kind before traversing list/map/buffer payloads.
  - Fixes a real crash where conservative stack scanning could misclassify a pointer and dereference a non-list/non-map allocation.

## Archived (2025-12-20) — CBOR serde streaming helpers (typed sequences)

- Added serde-friendly typed streaming helpers to `lib/std/cbor.oren`:
  - `cbor.encode_sequence_typed(items, Type__cbor_encode)`
  - `cbor.decode_next_typed(bytes, pos, Type__cbor_decode)`
  - `cbor.decode_sequence_typed(bytes, Type__cbor_decode)`
- Added integration test: `tests/modules/test_cbor_serde_streaming.oren`.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — YAML serde adaptor v1 (deterministic subset)

- Added `lib/std/yaml.oren`:
  - deterministic YAML emitter (block style, sorted keys, 2-space indent)
  - deterministic subset decoder (mappings + sequences + scalar types), plus JSON-text fallback (YAML 1.2 JSON subset)
  - audit reference: `docs/refs/yaml/yaml-1.2.2.html`
- Extended serde lowering to support `@serde(format="yaml")`:
  - generates `<Type>__yaml_encode` / `<Type>__yaml_decode`
  - representation matches JSON tagged value shape (`YamlValue` == `JsonValue` shape)
- Added integration test `tests/modules/test_yaml_serde_attrs.oren` and wired it into `cmd/oretest`.
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

## Archived (2025-12-20) — Stdlib math + regex v1 (portable, deterministic)

- Added `lib/std/math.oren`:
  - int helpers: `abs_i`, `min_i`, `max_i`, `clamp_i`
  - float helpers: `abs_f`, `min_f`, `max_f`, `clamp_f`, `is_nan`
- Added `lib/std/regex.oren`:
  - deterministic Thompson NFA engine (no backtracking blowups)
  - syntax v1: literals, `.`, `?`, `*`, `+`, `|`, grouping `( )`, anchors `^` `$`, classes `[a-z]` / `[^...]`, escapes via `\\`
- Tests:
  - added `tests/modules/test_math.oren` + `tests/modules/test_regex.oren`
  - wired into `cmd/oretest/main.go`
- Verified: `make test` on macOS + linux docker runner (`./tools/oretest_linux_docker.sh`) pass.

# TODOs (Rolling, Prioritized)

This repo is in **rolling ABI** mode (no version gates yet). This file is the canonical “what to do next” checklist for engineering execution.

Last updated: 2025-12-17

Focus statement (to avoid roadmap thrash):

- AVM is an **agent execution substrate** (deterministic, capability-governed, multiverse-friendly), not a near-term “general runtime for other languages”.
- Native backend is **syscall-first** (no libc/pthreads shims) so Oren can build real production libraries in `.oren`.

## P0 (Emergency / Blocking Safety)

### Cross-cutting (prevents hangs / makes rolling safe)

1) **Hard timeouts in test runner + CLI**
   - Any test that can block on PROC/NET must run under a timeout.
   - This is non-negotiable in rolling mode: a single hang kills iteration velocity.
   - Baseline:
     - `make test` uses `timeout` for native/AVM invocations where a hang is possible.
     - `avm` also supports an in-process wall-time budget: `--timeout-ms N` (or `AVM_TIMEOUT_MS`) so tooling/users don’t rely only on external `timeout`.
     - add a short per-test timeout for spawn/system and a longer global suite timeout (done; see `SUITE_TIMEOUT_SECS` in `Makefile`).

2) **SOLID refactors for “debuggable production”**
   - Goal: keep compiler/runtime modules small enough that invariants (stack/heap/scope/ABI) are auditable.
   - Refactor trigger: any single compiler module > ~2000 LOC must be split by responsibility (SOLID).
   - Status (compiler):
     - `lib/compiler/codegen_arm64.oren` refactor completed into focused modules (SOLID split):
       - `lib/compiler/arm64_core.oren` (byte utils, scope helpers, insn encodings, emit helpers) (~549 LOC)
       - `lib/compiler/arm64_native_expr.oren` (expression lowering; delegates syscall lowering) (~1308 LOC)
       - `lib/compiler/arm64_native_expr_syscalls.oren` (syscall lowering; helper used by `arm64_native_expr.oren`) (~1903 LOC)
       - `lib/compiler/arm64_native_stmt.oren` (statement lowering) (~782 LOC)
       - `lib/compiler/arm64_native_program.oren` (program entry lowering + symbol table generation) (~260 LOC)
       - `lib/compiler/codegen_arm64.oren` is now a thin facade for legacy imports
       - `lib/compiler/renamer.oren` (module rename pass)
       - `lib/compiler/arm64_macho.oren` (Mach-O emit + codesign blob builder)
       - `lib/compiler/arm64_elf.oren` (ELF emit)
     - Next watch item (SOLID): if `lib/compiler/arm64_native_expr_syscalls.oren` grows past ~2000 LOC, split by syscall domain (FS vs NET vs PROC vs TIME) so invariants remain auditable.

3) **First-class functions: function values + lambdas (must)**
   - Why it is P0:
     - required for real library design (callbacks, iterators, schedulers, async/concurrency)
     - required for compiler modularity (passing `compile_expr` callbacks avoids cyclic imports cleanly)
   - Status (bootstrap/C backend):
     - runtime supports `OREN_TYPE_FUNC` + `oren_func(...)` + `oren_call_obj(...)` dispatch
     - both transpilers (Go bootstrap + self-hosted `lib/compiler/transpiler.oren`) emit wrapper entrypoints `__oren_fnwrap` and wrap known functions into first-class values
     - parser supports lambda syntax: `|params| expr_or_block` and `|| expr_or_block` (empty params)
     - closures (lambdas) are fully executable on the C backend:
       - auto free-var capture, **capture-by-value** (v0)
       - runtime helper `oren_closure(...)` builds a GC-managed env list
       - `spawn` lowers to `oren_spawn_call_list(...)` so closures/function-values can be spawned (not just direct symbols)
   - Remaining (still mandatory):
     - bytecode backend: represent function values + closures and implement indirect call op
     - closure capture rules + determinism (captured values, env layout) must be part of the spec
   - Status (native backend):
     - runtime supports first-class callable objects (`oren_func(code_ptr, env_ptr)`, tracked kind=6; GC marks `env_ptr`)
     - compiler collects lambdas and emits wrappers:
       - `__oren_lambda_<N>(__env, __args)` for lambda bodies + capture binding
       - `__oren_fnwrap_<name>(__env, __args)` for named functions
     - indirect calls are implemented via `blr` to the wrapper code pointer
     - `spawn` lowers to `oren_spawn_call_list(fn_obj, args_list)` so closures/function-values can be spawned
     - regression: `tests/native/test_lambda_closure_native.oren`

### Native backend (syscall-first runtime; macOS-first; production-critical)

2) **Syscall-first OS boundary must be complete enough for “real programs”**
   - Goal: native Oren can build production libraries without libc shims:
     - FS + PROC + ENV + TIME + NET are the minimum “OS substrate”.
   - Enforce via tests and by keeping everything behind `sys_*`/`oren_*` boundaries.

3) **Syscall-first PROC + ENV correctness (no libc; macOS arm64)**
   - Blocking: if PROC/ENV is wrong, `spawn`, `oren_join`, and `oren_system` can hang or misbehave.
   - Requirements:
     - `oren_system()` must pass the intended child argv (`["sh","-c",cmd]`) and must never accidentally launch an interactive shell.
     - Preserve/forward parent environment to `execve` without libc:
       - capture `envp` at entry (preferred)
       - fallback derivation from `argv/argc` is allowed only as backup
     - `oren_getenv(key)` must be bounded (never hangs if envp is malformed/unterminated).
   - Regression tests:
     - `oren_system("echo ...")` completes quickly (guard with timeout).
     - `oren_getenv(...)` returns quickly for missing keys and returns non-zero for a known-set key (when present).
     - malformed key must not hang `oren_getenv` (unterminated string pointer regression: `tests/native/test_getenv_malformed_key.oren`).
     - `sys_execve(..., envp)` overrides env and `oren_system(...)` inherits it (regression: `tests/native/test_env_execve_getenv.oren`).
     - cancellable `system` wrapper kills + reaps on timeout: `tests/native/test_system_timeout.oren`.

4) **Syscall-first TIME substrate (native; no libc)**
   - Needed for production libraries to be self-contained (retries, backoff, polling loops) and to avoid “block forever” in higher-level PROC/NET wrappers.
   - “Best option” for native (host) time is:
     - monotonic for deadlines/backoff logic
     - wall/unix time only for logging/telemetry (not for correctness)
   - Minimal v0 surface (OS boundary):
     - `sys_nanosleep(ns) -> 0_or_neg_errno`
       - macOS implementation uses `kqueue + kevent(timeout)` (no libc shim).
       - Linux implementation uses `__NR_nanosleep` (aarch64).
     - `sys_gettimeofday(tv_ptr, tz_ptr, abs_ptr) -> 0_or_neg_errno`
       - macOS syscall provides a 3rd out-param `mach_absolute_time` (used as monotonic “raw” time).
       - Linux syscall provides `gettimeofday(tv, tz)` (no abs time); pass abs_ptr=0.
   - Runtime helpers:
     - `oren_sleep_ns(ns)` / `oren_sleep_ms(ms)`
     - `oren_time_unix_ns() -> int` (wall time)
     - `oren_time_mono_raw() -> int` (monotonic raw ticks; compare-only)
   - Status: implemented + regression:
     - `tests/native/test_sleep_ms.oren` (smoke)
     - `tests/native/test_time_now.oren` (unix wall time)
     - `tests/native/test_time_mono_raw.oren` (monotonic raw; compare-only)
     - `tests/native/test_system_timeout.oren` (wait4 WNOHANG + sleep + kill + reap)

5) **Native TCP/IP syscalls (macOS arm64) — minimal, correct, cancellable**
   - Mandatory for the final product: native Oren needs real TCP/IP without libc wrappers.
   - Minimal syscall-first surface (exact naming can evolve, but keep the boundary small):
     - `sys_socket`, `sys_connect`, `sys_bind`, `sys_listen`, `sys_accept`
     - `sys_send`, `sys_recv`, `sys_shutdown`, `sys_setsockopt`, `sys_getsockopt`, `sys_getsockname`, `sys_getpeername`
     - `sys_poll`/`sys_select` or `sys_kevent` for timeouts/cancellation (macOS-friendly: `kqueue/kevent`)
   - Runtime-level API (so `.oren` stdlib can build on it):
     - `oren_tcp_connect(ip, port, timeout_ms)` (v0 can start with IPv4 dotted quad only; DNS can come later)
     - `oren_tcp_read(fd, n, timeout_ms)` / `oren_tcp_write(fd, bytes, timeout_ms)` / `oren_tcp_close(fd)`
   - Must integrate with deadlines/timeouts (no “block forever”).
   - Status (macOS): implemented syscall-first TCP core + kqueue/kevent timeouts, plus a loopback regression test:
     - `sys_socket`, `sys_connect`, `sys_bind`, `sys_listen`, `sys_accept`
     - `sys_sendto`, `sys_recvfrom`, `sys_shutdown`, `sys_setsockopt`, `sys_getsockopt`
     - `sys_kqueue`, `sys_kevent`, `sys_fcntl`
     - `.oren` helpers: `oren_tcp_connect`, `oren_tcp_listen_local`, `oren_tcp_accept`, `oren_tcp_read_into`, `oren_tcp_write_from`, `oren_tcp_close`
     - test: `tests/native/test_tcp_loopback.oren`
     - minimal HTTP GET helper built on top of TCP syscalls:
       - `oren_net_get("http://<ipv4>[:port][/path]")` (v0; no TLS/DNS/chunked)
       - regression: `tests/native/test_http_get_loopback.oren`
   - Remaining (still required by the “real stdlib NET” goal):
     - add `sys_getsockname` + `sys_getpeername` (useful for debugging/introspection) (done; regression: `tests/native/test_tcp_sockname_peername.oren`)
     - add `sys_send`/`sys_recv` first-class intrinsics (may lower to sendto/recvfrom with NULL addr) (done; regression: `tests/native/test_tcp_send_recv.oren`)
     - add Linux syscall lowering for the same surface (see P0.6)

6) **ABI hygiene for rolling native runtime globals + pointer arithmetic**
   - Blocking: silent ABI slot collisions can deadlock/hang (hard to debug).
   - Rules (must be enforced/documented):
     - Never reuse a globals slot for two unrelated purposes.
     - Prefer named getters/setters (`global_get_*`) over raw offsets.
     - In native runtime `.oren`, use `iadd(ptr, off)` for pointer arithmetic; avoid `ptr + off` when `ptr` is a pointer value.
     - Entry stub must preserve its own state across runtime calls until native codegen preserves callee-saved regs (AAPCS).
   - Status (macOS native runtime): globals layout is centralized (named offsets + reserved slack), and allocator/thread tracking uses `iadd(...)` for struct offsets (`lib/runtime_native.oren`).
   - Status (native backend ABI):
     - native backend generic calls now follow AAPCS64 arg passing: X0..X7 + stack args for arg8+, and function prologues correctly load arg8+ from caller stack.
     - regression: `tests/native/test_call_stack_args.oren` (also in Docker Linux smoke list).

7) **Native memory hygiene: libc-free allocator + no leaks**
   - Native backend must remain libc-free (no `libc malloc/free`).
   - The compiler intrinsic `malloc(...)` is an internal runtime primitive (implemented on top of syscalls); user/library code should migrate toward type-driven allocation (constructors/literals) and avoid raw `malloc` calls.
   - Enforce correctness:
     - de-duplicate tracking records (no two GC nodes may point at the same ptr)
     - keep runtime metadata (globals/thread bookkeeping) out of GC-managed allocations
     - ensure `free(ptr)` works even when GC scanning is disabled (`--no-gc`)
   - Regression: `tests/native/test_gc_reuse_tracking.oren`

7) **Linux arm64 native backend parity (mandatory; avoid divergence)**
   - The production goal includes Linux; verify early to avoid “macOS-only drift”.
   - Deliverables:
     - implement Linux syscall lowering for the same `sys_*` surface (FS/PROC/ENV/TIME + NET sockets)
     - add a script to run a Linux native smoke subset on the trusted QEMU host (`blu@qemu-blu.localc`)
     - keep a short “Linux native smoke list” of tests that cover spawn/system/env/net basics
   - Status (rolling):
     - Linux syscall lowering is started for NET socket syscalls (socket/connect/bind/listen/accept/sendto/recvfrom/getsockopt/setsockopt/getpeername/getsockname/shutdown) + `fcntl` in `lib/compiler/arm64_native_expr.oren` (numbers referenced from `docs/refs/linux_asm_generic_unistd.h`).
     - Linux PROC syscall lowering is started for fork/exec/wait: `sys_fork` uses `clone(SIGCHLD, stack=NULL)`, `sys_execve` uses `__NR_execve`, `sys_wait4` uses `__NR_wait4` (refs: `docs/refs/linux_man_clone.2`, `docs/refs/linux_asm_generic_unistd.h`).
     - Linux TIME/PROC hygiene (rolling):
       - `sys_nanosleep` uses `__NR_nanosleep` (enables `oren_sleep_ms` and polling-based timeouts).
       - `sys_kill` uses `__NR_kill` (enables “timeout => kill + reap” patterns).
     - Linux smoke runner exists (preferred on macOS): `tools/linux_native_smoke_docker.sh` (Ubuntu 24.04 `linux/arm64`, per-binary `timeout`, container reuse via `OREN_DOCKER_KEEP=1`).
     - Linux smoke runner (optional / unstable): `tools/linux_native_smoke_qemu.sh` (trusted host, but may flap; keep as backup).
     - Regression coverage (Docker smoke):
       - PROC spawn/join works: `tests/native/test_spawn_simple.oren`, `tests/native/test_spawn_args.oren`
       - TIME+PROC timeout works: `tests/native/test_sleep_ms.oren`, `tests/native/test_system_timeout.oren`
       - TCP loopback with fork works: `tools/bench/test_linux_tcp_loopback_fork.oren`

### AVM (agentic execution substrate; safety + multiverse)

7) **Capsule must be “no host effects” by default**
   - Goal: when running `avm --capsule` (untrusted), **do not touch the host** even if the bytecode requests FS/PROC/NET and you choose to allow those domains.
   - Enforce by defaulting capsule runs to Virtual* backends unless explicitly overridden:
     - `fs_backend=vfs`
     - `proc_backend=vproc`
     - `net_backend=vnet` (host NET remains not implemented in bootstrap)
   - This prevents accidental “allowed FS means host FS” mistakes in governance workflows.

8) **Virtual backends (no-host effects) for safety + multiverse**
   - Goal: allow AVM programs (and nested universes) to use FS/PROC/NET-like APIs **without touching the host** (even in “record” runs).
   - This is required for:
     - safe “Matrix” simulation (thousands of sandboxes)
     - deterministic replay across swarm nodes
     - running untrusted plugins without giving host FS/PROC
   - Clarify contract (domains vs backends):
     - capability domains define *what effect is requested* (FS/NET/PROC)
     - backends define *where it executes* (virtual vs host)
     - “virtual by default” is a policy choice (capsule/simulation), not a redefinition of the domains
   - Minimal order:
     - VirtualFS (in-memory) for FS domain (read/write string + bytes), with IO/log budgeting and deterministic behavior
     - VirtualPROC fixture backend (no real subprocesses; deterministic fixture responses) for PROC domain
     - VirtualNET fixture backend (scripted request/response) for NET domain
     - Nested-universe fixture injection as data (`cfg.vfs_fixtures`, `cfg.proc_fixtures`, `cfg.net_fixtures`)
   - Must bind the chosen backend mode + fixtures into `exec_hash_sha256` / job objects (so consensus sees “what environment was used”).
   - Nested universes must support two modes cleanly:
     - **simulation mode:** virtual backends only (default; deterministic; snapshot-friendly)
     - **live mode:** allow explicit `*_backend=host` (direct host mapping; no relay) under strict subset rules (caps/allowlists/budgets), bound into `exec_hash`

9) **Governance-ready job object (bind to program + inputs + exec context)**
   - `--print-policy*` is scan-before-execute (no bytecode execution) and now outputs a stable `policy_hash_sha256` (`schema: avm.policy.v1`).
   - Added `--print-job` / `--print-job-json` (schema `avm.job.v1`) which computes `job_hash_sha256 = H(program_hash, policy_hash, input_hash)` without executing bytecode.
   - Updated `--print-job*` to schema `avm.job.v2`: `job_hash_sha256 = H(program_hash, policy_hash, input_hash, exec_hash)` where `exec_hash` binds effective allowlists + fs prefixes + budgets + deterministic knobs.
   - Updated `--print-job*` to schema `avm.job.v4`: `exec_hash` also binds requested output surfaces (trace bytes/hash, record-log hex, snapshot-out enablement, trace limits) plus FS backend selection (`host|vfs`).
   - Updated `--print-job*` to schema `avm.job.v5`: `exec_hash` also binds PROC backend selection (`host|vproc`) and `proc_exit_code` when `vproc` is selected.
   - Updated `--print-job*` to schema `avm.job.v6`: `exec_hash` also binds NET backend selection (`host|vnet`) and `net_fixtures_hash_sha256` when fixtures are provided.
   - Updated `--print-job*` to schema `avm.job.v7`: `exec_hash` also binds VirtualPROC fixtures (`proc_fixtures_hash_sha256`) when fixtures are provided.
   - Next: treat `job_hash` as the swarm consensus key (signatures/attestations are a later layer; don’t block bootstrap).

10) **Diagnostics must not affect semantics**
   - Tracing/profiling must be best-effort and must not change VM outcome.
   - In particular: trace-bytes capture should truncate/disable on budget exhaustion (do not abort the VM).
   - Also: trace-bytes capture must not consume `AVM_MEM_BYTES` (program heap budget); it should be governed by `AVM_TRACE_BYTES` instead.

11) **Native backend control-flow correctness (break/continue)**
   - Blocking: missing `break`/`continue` causes infinite loops and can manifest as “hangs” in syscall-first runtime code (e.g. parsers, scanners).
   - Implement in native backend codegen with correct stack hygiene and loop nesting support.
   - Status (macOS native + bytecode backend):
     - native backend: `while` and `for` support `break`/`continue` with proper nesting; `continue` in `for` runs `post`.
     - bytecode backend: `while` and `for` support `break`/`continue`, and function locals are pre-allocated so var-decls inside loops don’t grow the VM stack.
   - Status (native backend locals hygiene):
     - native backend now enforces lexical block scoping for locals in codegen (restores locals bindings when leaving a block), preventing stale SP-relative offsets from aliasing later locals (critical for `if pid==0 { ... }` patterns in syscall-first code).

12) **Deterministic maps: key-ordered storage**
   - For consensus and replayability, maps must not rely on insertion order (which can vary by compilation/lowering) or pointer-based ordering.
   - Contract (v0):
     - Map keys are restricted to `nil/bool/int/string` (reject other key types).
     - Maps store keys in deterministic ascending order: `nil < bool < int < string`, with strings ordered by bytewise compare (`strcmp`).
     - Duplicate key behavior: last assignment wins.
   - Enforced in:
     - AVM map construction (`NEW_MAP`) + map set (`SET_INDEX`)
     - AVM map get (`GET_INDEX`) uses the same key contract (binary search over ordered keys; rejects unsupported key types)
     - Native runtime `oren_map_set` (string keys)
     - C runtime `oren_new_map` + map set via `oren_index_set`
   - Regression: `tests/avm/test_map_key_order.oren` compares nested-universe `state_hash` across different insertion orders.
   - Regression: `tests/avm/test_map_key_types.oren` covers `nil/bool/int/string` keys, checks `result_hash` + `state_hash` across different insertion orders.

13) **`for x in ...` must be generic (rolling iterator hook)**
   - Goal: `for <name> in <iterable> { ... }` works uniformly across backends and container types needed for stdlib work.
   - Current implementation (rolling):
     - parser desugars to a `for init; cond; post { ... }` that calls `oren_iter_next(container, idx) -> [ok:int, value]`.
     - Implemented across:
       - native backend runtime (`lib/runtime_native.oren`): list/map/string
       - C backend runtime (`lib/runtime.c`): list/map/string
       - AVM core natives (`lib/avm/avm_native.inc` id 43): list/map/string/bytes
   - Current semantics:
     - `list`: yields elements in index order
     - `map`: yields keys in deterministic key order
     - `string`: yields byte codepoints (`0..255`)
     - `bytes` (AVM): yields u8 values (`0..255`)
   - Next (still required for the “streams everywhere” goal):
     - define an iterator/stream protocol beyond built-in containers (e.g. `Stream` type, channel receive iteration, and/or a `__iter_next` callable contract) and bind it into determinism/capabilities.

14) **Struct field immutability (portable semantics)**
   - Why it matters:
     - backends currently differ in struct representation (maps vs contiguous buffers)
     - allowing `obj.field = v` makes semantics ambiguous and risks backend-specific behavior
   - Contract (rolling):
     - `obj.field` is **read-only** field access
     - `obj.field = v` is a **compile-time error**
     - use `xs[i] = v` / `m[key] = v` for mutation (lists/maps), and construct a new struct value instead of mutating
   - Status: implemented as a parser error (fixture: `tests/native/fixtures/struct_field_assign_bad.oren`).
   - Next (design; no rewrite path):
     - introduce a persistent “update” form for structs (e.g. `p2 = p with { x=..., y=... }` or `p2 = Point(p.x, newy)`), after traits/enums stabilize.

15) **AVM call stack discipline (CALL/RET must not leak stack)**
   - Production-blocking correctness: without proper stack restoration on `RET`, even trivial function calls corrupt stack state and can grow without bound.
   - Contract (rolling):
     - `CALL addr,nargs` consumes `nargs` arguments and (on return) leaves **exactly one** value on the caller stack.
     - `RET` discards the entire callee frame (args/locals/temps) and pushes the return value for the caller.
   - Status: implemented in the AVM interpreter (`lib/avm/avm_vm.c`) with a regression `tests/avm/test_call_stack_discipline.oren`.

16) **Test suite scalability (reduce redundant compiles; keep coverage)**
   - Problem: `make test` compiles+links each `.oren` file separately; many “atomic” tests overlap and some are implicitly covered by more complex ones.
   - Goal: keep iteration velocity high while preserving correctness coverage.
   - Approach (rolling):
     - keep “atomic” tests as files (debuggable, bisect-friendly)
     - add “suite” tests that cover a whole domain in one binary (NET, TIME, PROC/ENV, etc.)
     - run a curated list by default (`make test`), and keep an escape hatch to run everything (`make test-native-all`)
   - Status:
     - added `tests/native/test_net_suite.oren` (TCP loopback + send/recv intrinsics + sockname/peername + HTTP GET loopback)
     - added `tests/native/test_time_suite.oren` (sleep + unix time + monotonic raw)
     - `make test` now runs a curated native list; `make test-native-all` runs the full glob.
     - `make test` now runs a curated AVM list (see `AVM_TESTS` in `Makefile`); override with `make test AVM_TESTS="tests/avm/*.oren"` for full AVM coverage.

17) **Native stdlib modules (syscall-first; no libc)**
   - Goal: “real code” in `.oren` should import stable modules instead of calling raw `oren_*` helpers directly.
   - Status (rolling, macOS-first):
     - added `lib/std/net/http.oren` with `http.get(url)` backed by `oren_net_get(url)`
     - native backend now supports module namespace resolution for expressions and calls (e.g. `http.get(...)`), matching the C-backend `ns_resolve` flattening convention.

## P1 (High Leverage for Agentic Debugging / Swarm)

1) **AVM deterministic cooperative tasks (concurrency model; mandatory for agents)**
   - This is the production “agent loop” primitive: structured concurrency without OS-thread nondeterminism.
   - Implement a single-threaded deterministic scheduler first (FIFO ready queue + deterministic wake ordering).
   - Minimal surface (design in `docs/AVM_CONCURRENCY.md`):
     - spawn/join tasks
     - channels + select
     - integration with budgets + deterministic TIME + snapshot/restore

2) **Deterministic trace as data + `TRACE_HASH`**
   - Encode trace events into `BYTES` deterministically.
   - Hash trace stream for k-of-n validation and agentic diffing.
   - Bootstrap status:
     - `avm --print-trace-hash` exists.
     - `avm --print-trace-bytes-hex` exists (hex transport).
   - Next: extend event categories (alloc/error object metadata/spans) and add a BYTES return channel (not only hex dump).

3) **Language meta-system: unified attributes (decorators + field annotations)**
   - Direction is documented in `docs/LANGUAGE_SPEC.md` (“Meta / Attributes”) and is required for:
     - user- and library-defined metadata (docs/IDE tooling)
     - governance-friendly APIs (`@cap.requires(...)`)
     - future derive-style codegen (`@derive(...)`) without “Python runtime decorator” semantics
     - AVM tooling (disasm/debug/profiling correlation) once metadata is embedded in `.obc`
   - Minimal no-rewrite implementation stages:
     - M1: parse and preserve `@attr(...)` on function/type declarations in the compiler AST (ignored for semantics). (done; regressions: `tests/native/test_attributes_noop.oren`, `tests/avm/test_attributes_noop.oren`)
     - M2: allow field/param attributes (still metadata-only). (done; regressions: `tests/native/test_attributes_fields_params.oren`, `tests/avm/test_attributes_fields_params.oren`)
     - M3: strict mode (`--strict-attrs` / env) where unknown attributes are a compile error unless declared/allowed. (done; regressions: `tests/native/fixtures/strict_attrs_ok.oren`, `tests/native/fixtures/strict_attrs_bad.oren` via `make test`)
     - M4: `.obc` metadata section (attributes + names) plus separate `meta_hash`:
       - `program_hash` remains semantics-only (code + constants), must not include inert metadata.
       - `meta_hash` covers metadata for auditing/debugging.
     - M5: surface attributes in `avm --disasm-json` / `--inspect-json` (tooling must not execute bytecode).

4) **Object model scaffolding: traits/protocols + composition (no inheritance-first)**
   - Direction is documented in `docs/OBJECT_MODEL.md` and `docs/LANGUAGE_SPEC.md` (“Object Model”).
   - Goal: make syscall-first boundaries and AVM virtualization natural:
     - define `FS/NET/PROC/ENV/TIME` as traits and pass explicit capability objects (instead of implicit globals).
   - Minimal no-rewrite implementation stages:
     - T1: `trait` declarations as compile-time contracts (no runtime rep; no dynamic dispatch yet).
     - T2: `impl Trait for Type` + static dispatch where concrete types are known.
     - T3: optional trait objects (explicit opt-in) for dynamic dispatch (plugins).
     - T4: `enum` + `match` for ADTs (agent workflow state machines), later exhaustiveness checks.

5) **NET domain contract + replay/fixture story (AVM)**
   - Keep NET semantics virtualizable and deterministic by design:
     - VirtualNET fixtures remain the default for capsules and nested universes.
     - define a canonical request shape (recommended: HTTP-ish request/response rather than raw sockets).
   - Add record/replay for NET domain (so “real host net” can be audited where allowed).
   - Ensure task scheduler integrates NET as an async/blocking op (no blocking forever).

6) **Handle delegation (fd/socket passing) — later explicit mode**
   - Do not attempt this in v0 capsule/deterministic mode.
   - If added later, it must be an explicit opt-in flag (e.g. `host_handles_allowed=1`) bound into `exec_hash`, with clear snapshot portability limits.

7) **Snapshot/restore “capsule” hardening**
   - Move toward capsule-friendly formats (hashable, resumable, policy-bound).

8) **“AVM as Oren built-in library” (libavm embedding)**
   - Mandatory for the “embed libavm + oren.obc on iOS/edge” story (`docs/OREN_EVOLUTION.md`).
   - Minimal no-rewrite path:
     - stabilize a small `libavm` C API: `avm_run_bytes(...) -> {result, hashes, record_log_bytes, snapshot_bytes}`
     - provide Oren bindings in a standard module (so Oren programs can spawn child universes without shelling out)
     - start with C-backend integration (link `libavm` into `lib/runtime.c`) and keep native-backend integration as a follow-up.

9) **Compiler-in-AVM (“source -> .obc inside a child universe”)**
   - Mandatory for closing the loop (multiverse + in-memory compilation) without a host toolchain.
   - Break into minimal milestones to avoid massive rewrites:
     - M1: get a small “compiler capsule MVP” that compiles a single-file `.oren` subset to `.obc`, using VirtualFS for IO.
     - M2: extend to imports/modules, deterministic compilation mode, and returning `.obc` as `BYTES`.
     - M3: use this path to compile AVM-facing stdlib modules inside the sandbox.

10) **Tooling: disassembler + debugger + profiler**
   - Disassembler: stable “otool-like” `.obc` inspector (sections, consts, policy, hashes).
   - Debugger: minimal “lldb-like” stepping + breakpoints + trace correlation (pc/op/stack depth).
   - Profiler: memory/time attribution surfaces that are deterministic / loggable (must not change semantics).
     - Bootstrap progress: trace stream now includes bytes-only `ALLOC/FREE/REALLOC` events (not included in `TRACE_HASH`) and `tools/avm_trace_profile.py` can decode `TRACE_BYTES_HEX` into an allocation profile JSON.

11) **Native backend concurrency: N:1 greenlets first, then N:M GMP (no shims)**
   - Keep native backend free of libc/pthreads shims for core runtime services.
   - Current v0 `spawn` uses `fork + pipe` (process-based) for correctness.
   - Next (no huge rewrite path, see `docs/NATIVE_GMP_SCHEDULER.md`):
     - N:1 stage: cooperative greenlets + explicit `yield` + non-blocking IO (kqueue/kevent on macOS).
     - N:M stage: syscall-first OS threads + parking/unparking + work stealing + GC coordination.

12) **Compile-time evaluation (“comptime”) — pure-only first**

13) **Packed struct views over bytes (network parsing; zero-allocation)**
   - Goal: parse protocol headers without allocations and without exposing UB.
   - Motivation:
     - syscall-first networking wants low overhead and deterministic semantics
     - “allocation per packet” does not scale; a view is the correct primitive
   - Contract (design target; see `docs/LANGUAGE_SPEC.md`):
     - a packed view value is `{bytes, offset}` (immutable, non-owning)
     - field reads are endian-aware and bounds-checked
     - no host-endianness or unaligned loads; semantics must be stable under interpreter/JIT/native
   - Minimal milestones:
     - PV1: define schema via attributes (metadata-only), ignored by runtime
     - PV2: add a `pack_view(TypeName, bytes, offset)` intrinsic returning a view object
     - PV3: lower `view.field` reads to `oren_bytes_get_u{N}_{be|le}` based on schema metadata
     - PV4: allow nested packed views (e.g. IPv4 header contains options slice)
   - Goal: make compilation deterministic and agent-friendly without a huge rewrite.
   - Stage C0: constant evaluation for pure expressions only (no FS/NET/PROC/ENV/TIME, no nondeterministic RNG), with explicit budgets to prevent compiler hangs.
   - Later stages (pure comptime functions, bounded reflection) can follow once C0 is stable.

13) **Unify struct semantics across backends + plan escape analysis**
   - Production semantics target:
     - pass-by-immutable-value
     - struct value is an immutable handle (pointer-sized), not a stack-cloned blob
     - compiler uses escape analysis to decide stack vs heap placement
   - Unify backend representation:
     - C backend currently lowers `struct` constructors to maps (convenient but not layout-stable).
     - Native backend uses contiguous struct buffers (`oren_alloc_struct(n_fields*8)`).
     - Bytecode backend will need a consistent model as well.
   - Networking motivation:
     - enable “packed struct view over bytes” with explicit `@be/@le` field reads as a future no-allocation parsing path.

## P2 (Next-Gen AVM Performance + Features)

1) **Typed buffers + SIMD kernels (no-JIT-first path)**
   - Implement `F32_BUF` + minimal vector ops (`dot/add/mul/reduce`) with scalar fallback.
   - This is also the recommended path for **float32** support in v0 without adding a second scalar float tag to the dynamic value model.
   - Follow-up: define fixed-width numeric types (`i32/u32/u128`, `f32/f64`) primarily as typed-buffer element types and serialization/FFI boundary types.

2) **VirtualNET / VirtualPROC backends (fixtures)**
   - Enable “Matrix sandbox” simulation and deterministic replay of realistic workflows.

3) **Codebase factoring (do only when it prevents progress)**
   - AVM core has been split into SOLID-ish C modules under `lib/avm/` (e.g. `lib/avm/avm_vm.c`, `lib/avm/avm_native.c`, `lib/avm/avm_state.c`).
   - Future factoring should continue by capability domain (NET/PROC/FS/TIME/RNG) and by deterministic surfaces (hashing/tracing/snapshot), avoiding random churn.
   - Goal: factor by capability domains and by deterministic surfaces (hashing, tracing, snapshot) rather than “random file splitting”.

4) **NET_DIAG diagnostic ops (host-only first; ICMP; later ARP/neighbor table)**
   - Keep these out of the core NET substrate (TCP/UDP/DNS/TLS); they are diagnostics and frequently have privilege / platform constraints.
   - Design direction:
     - add a separate NET diagnostic capability catalog (`NET_DIAG`) (or NET domain ops with an explicit `diag.*` naming convention).
     - expose high-level APIs (not raw packet crafting) first:
       - `ping(ip, timeout_ms) -> {ok:bool, rtt_ms:int, ttl?:int, err?:map}`
       - `traceroute(ip, max_hops, timeout_ms) -> list[...]`
     - in AVM/capsule/multiverse mode: diagnostics must be virtualized (fixtures or record/replay), never “hit the real network” unless explicitly allowed and bound into `exec_hash`.
   - ICMP:
     - include ICMP echo/time-exceeded in the diagnostic catalog (not required for v0/v1 bootstrap).
     - note: raw ICMP often requires privileges; handle permission errors deterministically.
   - ARP / neighbor discovery:
     - defer; platform-specific and often requires link-layer access (BPF-like interfaces) or OS neighbor tables.
     - if implemented later, prefer “inspect neighbor table” capability (read-only) rather than “craft ARP frames”.

## Recently Completed (for context)

- Native panic traces: add pseudo symbols for `__top_level__` (top-level statement lowering) and `__entry_stub__` (arm64 entry shim) so stack traces are readable even without an explicit `fn main()`.

## 2025-12-20 (Recent)

- `oretest`: added a repeated-run determinism guard for `tests/avm/test_smoke_suite.oren` (rerun scalar mode, require `RESULT_HASH` + `TRACE_HASH` match).
- Docs: clarified that AVM FLOAT constants are wired end-to-end and documented const tag `3` as float64 bit-pattern in the bootstrap spec (`docs/AVM_SPEC.md`).
- Compiler: added `///` doc comments (lexer/parser) and exported docs in metadata JSON for functions/structs/traits (covered by `tests/modules/test_metadata_attrs.oren`).

## 2025-12-21 (Recent)

- Serde/format integration: added nested arrays+maps deterministic roundtrip coverage for JSON/YAML/CBOR (`tests/modules/test_format_nested_roundtrip.oren`).
