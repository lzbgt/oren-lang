# Oren Language Feature Matrix (Rolling, AI-Friendly)

**Last updated:** 2025-12-30  

This document is a **quick index** for AI agents and maintainers:

- what a feature is,
- whether it is **Implemented / Rolling / Planned**,
- where the implementation lives (compiler/runtime),
- where the behavior is validated (fixtures/examples).

It complements:

- `docs/LANGUAGE_MANUAL.md` (how to write Oren today),
- `docs/LANGUAGE_SPEC.md` (grammar + semantics),
- `docs/LANGUAGE_STATUS_AND_GAPS.md` (production gaps, evidence-backed).

Status legend:

- **Implemented**: supported by the Stage1 compiler and used in current code.
- **Rolling**: supported, but semantics/ABI may still evolve (must stay regression-tested).
- **Planned**: design intent; track via `docs/TODOS.md` / `docs/ROADMAP.md`.

## Core language

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| Modules + `import` | Rolling | Parser: `lib/compiler/parser_parse/**`; Linking: `lib/compiler/compiler/020_modules_linking.oren` | Examples: `examples/module_app.oren`; Tests: `tests/modules/` |
| Top-level statements + entry | Rolling | Native entry stubs: `lib/compiler/arm64_*`, `lib/compiler/x64_*`; Bytecode entry: `lib/compiler/codegen_bytecode/030_tail.oren`; C entry: `lib/compiler/transpiler.oren` | Tier‑1 x86_64 remote fixture (no `fn main`): `tests/fixtures/tier1_native_no_main_top_level_only.oren` (`OREN_REMOTE_RUN=1`) |
| Top-level globals (`var` at module scope) | Rolling | x86_64 native stores globals as 8-byte slots in the appended data blob and runs non-constant initializers in a synthesized `__top_level__` (`lib/compiler/x64_native_program/090_program_entry.oren`, loads: `lib/compiler/x64_native_program/040_emit_expr.oren`, stores: `lib/compiler/x64_native_program/060_emit_ops.oren`) | Tier‑1 x86_64 remote fixture: `tests/fixtures/tier1_native_globals_top_level_main.oren` (`OREN_REMOTE_RUN=1`) |
| Program termination (`exit`) | Rolling | x86_64 native lowers `exit(...)` to `sys_exit` (`lib/compiler/x64_native_program/046_emit_sys_intrinsics.oren`); other backends may still treat `main` return as advisory | Prefer `exit(code)` for portability; Tier‑1 x86_64 evidence: `tests/fixtures/tier1_native_globals_top_level_main.oren` (`OREN_REMOTE_RUN=1`) |
| `print(<string>)` statement | Rolling | Surface: statement-form `print(...)` call; x86_64 native supports literal and non-literal string expressions (strlen + `sys_write`): `lib/compiler/x64_native_program/047_emit_print_stmt.oren`, `lib/compiler/x64_native_program/046_emit_sys_intrinsics.oren` | Tier‑1 x86_64 remote fixture (non-literal arg): `tests/fixtures/tier1_native_smoke_main.oren` (`OREN_REMOTE_RUN=1`) |
| `fn` + named functions | Implemented | Parser + lowering + all backends | Everywhere; compile pipeline: `lib/compiler/compiler/040_build_pipeline.oren` |
| Function values + lambdas | Rolling | C backend: `lib/compiler/transpiler.oren` (closures + wrappers); Native runtime: `lib/runtime_native/120_first_class_fn.oren`; Bytecode: `lib/compiler/codegen_bytecode/**` | AVM: `tests/avm/test_closure_fn_values.oren` |
| Varargs (`...rest`) + spread calls | Rolling | Parser marks `is_varargs`; Bytecode/C/native lowering handle spread and rest list packing | Tier‑1 closure parity: `tests/fixtures/tier1_native_lambda_varargs_main.oren` (remote x86_64 gate via `OREN_REMOTE_RUN=1`) |
| Control flow: `if/else`, `while`, `for`, `switch/case` | Implemented/Rolling | Parser + lowering; `for x in ...` is sugar in lowering | Example: `examples/hello.oren`; Tests: `tests/native/` + `tests/avm/test_switch.oren` |
| `match` | Rolling | Parser contextual keyword + lowering into deterministic control flow | Tests: `tests/modules/test_match_enum.oren` |
| `enum` | Rolling | Lowered as tagged-map constructors | Tests: `tests/modules/test_match_enum.oren`; Spec: `docs/LANGUAGE_SPEC.md` “enum/match” section |

## Types and “static-first” constructs

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| Type annotations (syntax) | Rolling | Parser supports `: type_name`; lowering uses hints | Manual/spec: type annotation sections |
| Traits + impl blocks (static-first) | Rolling | Parser: `lib/compiler/parser_parse/**`; Lowering: impl rewrite passes under `lib/compiler/**` | Tests: `tests/modules/test_trait_*.oren` |
| `dyn` / runtime trait objects | Planned | Design docs (static-first + opt-in runtime polymorphism) | Track: `docs/TODOS.md` |
| Floats (`f64` container) + casts (`f32/f64/i64/u64/bool`) + comparisons + **bit-casts** (`u32↔f32`, `u64↔f64`) | Rolling | Front-end cast lowering: `lib/compiler/type_ann_lowering.oren`; Bytecode: `lib/compiler/codegen_bytecode/**`; C runtime helpers: `lib/runtime/050_io_misc.inc`; Native: arm64 `lib/compiler/arm64_native_expr/**`, x86_64 `lib/compiler/x64_native_program/047_emit_float_intrinsics.oren` + `lib/compiler/x64_native_program/050_emit_cmp_labels.oren` + `lib/compiler/x64_native_program/040_emit_expr.oren` (bit-cast intrinsics) | Tier‑1 x86_64 fixture: `tests/fixtures/tier1_native_float_ops_main.oren` (remote gate via `OREN_REMOTE_RUN=1`); SIMD suite exercises float kernels: `tests/native/test_simd_suite.oren` |

## Containers and performance

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| List literal `[]` and indexing `xs[i]` | Rolling | Shared lowering + backend intrinsics; C uses runtime helpers | Tests: `tests/native/fixtures/**`; Docs: `docs/DESIGN_CONTAINER_OPS.md` |
| List `push/len` as operations (no wrapper overhead) | Rolling | Lowering: `lib/compiler/impl_lowering.oren`; Intrinsics: `oren_list_len`, `oren_list_push` (returns `nil`) | Track: `docs/TODOS.md` (P0.4); Internals: `docs/IMPLEMENTATION_NOTES.md` |
| `slice_view` / `clone` / `slice_copy` | Rolling | Stdlib: `lib/std/list.oren` (`clone`, `slice_copy`, `slice_view`) | Manual: `docs/LANGUAGE_MANUAL.md` (List helpers); Track: `docs/TODOS.md` (P0.4) |
| Map literal `{}` and indexing `m[k]` / `m[k]=v` | Rolling | Parser + lowering; C/AVM: dynamic keys; Native: key-kind must be deterministic | Tests: `tests/native/test_integration_suite.oren`; Manual: `docs/LANGUAGE_MANUAL.md` “Maps” |
| Map dynamic string keys on empty maps (Tier‑1 x86_64) | Rolling | x64 native uses tracked-allocation metadata for key-kind inference; no syntax heuristics | Tier‑1 remote fixture: `tests/fixtures/tier1_native_map_dynamic_keykind_main.oren` (requires `OREN_REMOTE_RUN=1`) |
| Map get with dynamic string key (Tier‑1 x86_64) | Rolling | x64 native map lookup must infer key kind from value metadata and perform string compare when needed | Tier‑1 remote fixture: `tests/fixtures/tier1_native_map_get_dynamic_key_main.oren` (requires `OREN_REMOTE_RUN=1`) |
| Deterministic map iteration | Rolling | C runtime keeps keys sorted; native runtime sorts lazily on demand; x86_64 native still has a bring-up path that sorts on-demand inside `oren_iter_next`, but can now opt into **full native runtime injection** behind `OREN_X64_INJECT_RUNTIME=1` | Tests: `tests/native/test_integration_suite.oren` (map iteration); Tier‑1 x86_64: `tests/fixtures/tier1_native_map_dynamic_keykind_main.oren` (`OREN_REMOTE_RUN=1`); Runtime: `lib/runtime_native/160_iteration.oren`, `lib/runtime_native/130_printing.oren` |
| Typed map ops (`oren_map_get_str/int`, `oren_map_set_str/int`) | Rolling | Native runtime: `lib/runtime_native/130_printing.oren`; C runtime: `lib/runtime/040_lists_maps.inc`; Native lowering selects typed ops when key kind is known | Used by stdlib codecs: `lib/std/json.oren`, `lib/std/yaml.oren`, `lib/std/cbor.oren` |
| Typed buffers `[]i32`, `[]f64`, ... | Rolling | Stdlib: `lib/std/buffer.oren` + runtime helpers | Docs: `docs/HPC_SERVER_PLAN.md` |
| Typed buffers `[]u8` in AVM (bytes-backed) + buffer views | Rolling | AVM core natives: `lib/avm/avm_native.inc` (`oren_u8_buf_new`, `oren_buf_*_u8`, `oren_iter_next` view handling); Bytecode lowering: `lib/compiler/codegen_bytecode/010_codegen_a.oren` | AVM test: `tests/avm/test_u8_buf_views.oren` |
| Typed buffers Tier‑1 native smoke (x86_64 Linux/Windows) | Rolling | Native runtime: `lib/runtime_native/typed_buffers/**`; x64 native: compiler intrinsics `lib/compiler/x64_native_program/049_emit_typed_buffer_intrinsics.oren` (uses x64 core load/store encoders in `lib/compiler/x64_core.oren`) | Tier‑1 remote fixture: `tests/fixtures/tier1_native_typed_buffers_main.oren` (`OREN_REMOTE_RUN=1`) |
| `for x in buf` + buffer views (`[buf,off,len]`, `[buf,off,len,stride]`) on Tier‑1 x86_64 | Rolling | Iterator intrinsic: `lib/compiler/x64_native_program/042_emit_iter_next_intrinsic.oren` (matches `lib/runtime_native/160_iteration.oren` view rules) | Tier‑1 remote fixture: `tests/fixtures/tier1_native_forin_typed_buffers_main.oren` (`OREN_REMOTE_RUN=1`) |
| Strings: concat (`+`), `len`, `slice` (Tier‑1 x86_64) | Rolling | C backend: string `+` via `oren_add` (`lib/runtime/030_ops_compare.inc`), plus `oren_string_len`/`oren_string_slice`; Native backend: `string_concat`/`oren_string_len`/`oren_string_slice`/`oren_string_eq` (`lib/runtime_native/150_strings.oren`, `lib/runtime_native/160_iteration.oren`); x64 native lowering: `lib/compiler/x64_native_program/046_emit_string_intrinsics.oren` | Tier‑1 remote fixture: `tests/fixtures/tier1_native_string_ops_main.oren` (`OREN_REMOTE_RUN=1`) |

## Runtime model (determinism, safety, AVM)

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| Deterministic diagnostics (`OREN_DIAG`) | Rolling | Runtime + emit points (native/C) | Fixtures: `tests/native/fixtures/diag_fail.oren` |
| Stack safety (call depth guard) | Rolling | AVM flag; C env; native guards | Docs: `docs/STACK_SAFETY.md`; fixtures: `tests/native/fixtures/call_depth_overflow.oren` |
| Tail-call optimization | Rolling (subset) | Lowering/codegen passes | Docs: `docs/STACK_SAFETY.md` |
| Native runtime injection (`lib/runtime_native.oren` expanded includes) | Rolling | Shared include expander: `lib/compiler/native_runtime_inject.oren`; arm64 native injects by default: `lib/compiler/arm64_native_program.oren`; x86_64 native injection is currently gated by `OREN_X64_INJECT_RUNTIME=1`: `lib/compiler/x64_native_program/090_program_entry.oren` | Local smoke: `OREN_X64_INJECT_RUNTIME=1 make test`; Tier‑1: `OREN_X64_INJECT_RUNTIME=1 OREN_REMOTE_RUN=1 make test` |
| Atomics (`atomic_add`, `atomic_cas`) | Rolling | ARM64: `lib/compiler/arm64_native_expr/**` (LL/SC lowering); x86_64: `lib/compiler/x64_native_program/040_emit_expr.oren` (LOCK XADD / CMPXCHG) | Native tests: `tests/native/test_atomics.oren`; Tier‑1 x86_64 fixture: `tests/fixtures/tier1_native_atomics_main.oren` (`OREN_REMOTE_RUN=1`) |
| Capsule model (native capability gating) | Rolling | Native runtime + syscall emit constraints | Fixtures: `tests/native/fixtures/capsule_*` |
| AVM execution of `.obc` | Rolling | Runtime: `lib/avm/**`; codegen: `lib/compiler/codegen_bytecode/**` | Examples: `examples/avm_*`; Tests: `tests/avm/**` |
| Capability domains (CORE/FS/NET/PROC/AVM) | Rolling | `.obc` verifier + dispatch: `lib/avm/avm_native.inc`, `lib/avm/main.c` | Spec: `docs/AVM_SPEC.md` (domains vs backends); fixtures cover capsule constraints |
| VirtualFS backend (`vfs`) for deterministic simulation | Rolling | Backend selection + fixtures: `lib/avm/main.c`; VFS ops + snapshot codec: `lib/avm/avm_native.inc` | Spec: `docs/AVM_SPEC.md` (VirtualFS / `AVMVFS01`) |
| VirtualPROC backend (`vproc`) for deterministic subprocess stubs | Rolling | Backend selection + fixtures: `lib/avm/main.c` | Spec: `docs/AVM_SPEC.md` (`AVM_PROC_BACKEND=vproc`, `AVM_PROC_FIXTURES_HEX=...`) |
| VirtualNET backend (`vnet`) for deterministic network stubs | Rolling | Backend selection + fixtures: `lib/avm/main.c` | Spec: `docs/AVM_SPEC.md` (`AVM_NET_BACKEND=vnet`, `AVM_NET_FIXTURES_HEX=...`) |
| `.obc` signature verification (`--require-sig`) | Rolling | Sig verifier: `lib/avm/avm_sig.c` | Spec: `docs/AVM_SPEC.md`; tools: `cmd/orensign/main.go` |
| Delegated signing via embedded cert chain (`OREN_CERTS`) | Rolling | Cert parser: `lib/avm/avm_cert.c`; chain verify: `lib/avm/avm_sig.c` | Docs: `docs/CERT_CHAIN_FORMAT.md`, `docs/APPSTORE_ROOTCA_AND_UPDATES.md` |
| Strict verification mode (`--verify-strict`) | Rolling | CLI + verifier gating: `lib/avm/main.c` | Spec: `docs/AVM_SPEC.md` (strict verification); help: `lib/avm/avm_help.inc` |
| Nested universes (“AVM in AVM” / multiverse host service) | Rolling (gated) | AVM domain dispatch: `lib/avm/avm_native.inc` (Domain 8: AVM) | Docs: `docs/AVM_MULTIVERSE.md` (model + constraints) |
| Swarm / consensus outcome hashing | Rolling (in progress) | Job hash + result selection: `lib/avm/avm_state.inc`, `lib/avm/avm.h` | Docs: `docs/AVM_SWARM_CONSENSUS.md` |
| Compiler-in-AVM | Planned | Bytecode compiler + AVM host interface constraints | Track: `docs/TODOS.md` (P0.10), `docs/TOOLCHAIN_SELF_HOSTING.md` |

## HPC / SIMD (Tier‑1 HPC: arm64 NEON now, x86_64 SSE/AVX next)

| Feature | Status | Where (impl) | Evidence / notes |
|---|---|---|---|
| Typed buffers (`[]i32`, `[]f32`, `[]f64`, …) | Rolling | Stdlib/runtime surfaces under `lib/std/buffer.oren` + `lib/runtime_native/typed_buffers/**` | Manual: `docs/LANGUAGE_MANUAL.md` (Typed buffers section) |
| Native SIMD toggle | Rolling | Native runtime parses `OREN_ENABLE_SIMD` / `OREN_NO_SIMD`: `lib/runtime_native/040_capsule_core.oren` | Test harness runs a scalar baseline with `OREN_NO_SIMD=1`, then a SIMD run with `OREN_ENABLE_SIMD=1` and compares outputs (`cmd/oretest/suites.go`) |
| SIMD determinism contract (scalar is authoritative) | Rolling | Runtime dispatch chooses scalar vs SIMD; tests enforce equivalence | Determinism guard: SIMD must remain bit-identical to scalar for covered kernels; reduction order is fixed (no reassociation). Primary suite: `tests/native/test_simd_suite.oren` |
| SIMD intrinsics (arm64 NEON) | Rolling (arm64 macOS/Linux); Planned (x86_64) | Native arm64 codegen lowers `simd_*` intrinsics: `lib/compiler/arm64_native_expr/**` | Spec lists the intrinsic family: `docs/LANGUAGE_SPEC.md` (“Native Backend Intrinsics”) |
| SIMD-backed typed-buffer kernels (dot/axpy/gemm/etc.) | Rolling (arm64 macOS/Linux); Planned (x86_64) | Runtime dispatch in `lib/runtime_native/typed_buffers/**` + arm64 intrinsic lowering | Opt-in via `OREN_ENABLE_SIMD=1` (or disable with `OREN_NO_SIMD=1`). Must remain deterministic. |
| x86_64 SIMD plan (SSE2 baseline, AVX2 optional) | Planned | x64 native codegen + runtime kernel implementations | Track under `docs/TODOS.md` (HPC item) until we have an x86_64 SIMD parity suite (scalar vs SIMD) and stable feature detection for Linux+Windows |
| AVM SIMD (NEON) | Planned / Rolling (gated) | Build/runtime gating exists (`AVM_ENABLE_SIMD=1`, arm64 NEON): `lib/avm/avm_native.c`, `lib/avm/main.c` | Design constraints: `docs/AVM_NEON_MAPPING_PLAN.md` (determinism-first); not treated as mature until fully covered by AVM tests |
| HPC roadmap (math/linalg + perf harness) | Rolling (in progress) | Design docs: `docs/HPC_SERVER_PLAN.md`, typed-buffer + linalg layers | Tracker: `docs/TODOS.md` (P1.3) |

## Tooling / ecosystem

| Feature | Status | Where (impl) | Evidence / examples |
|---|---|---|---|
| `oren` CLI subcommands + completion | Rolling | CLI: `lib/compiler/compiler/000_prelude.oren`; completion docs | Docs: `docs/CLI_COMPLETION.md` |
| Package registry (`oren-packages`) integration | Planned | Module resolution + lockfiles + reproducible builds | Track: `docs/TODOS.md`, `docs/ROADMAP.md` |
