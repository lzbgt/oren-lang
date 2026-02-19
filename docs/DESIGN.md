# Design + Toolchain (Language + Compiler + Runtime + AVM)

**Last updated:** 2026-02-19

This document is the lean, canonical design + toolchain reference. It merges the former
compiler/backend, runtime/stdlib, AVM, and toolchain/platform docs into one place.

Scope: high-signal facts that remain true in rolling mode. For exact semantics,
trust code + fixtures first (see `tests/` and `docs/STATUS.md`).

---

## System overview (rolling)

Oren is a self-hosted language + compiler with three execution backends:

- C backend: portable bootstrap path via a host C toolchain.
- Native backend: direct Mach-O/ELF/PE output (Tier-1 intent).
- Bytecode backend (OBC): `.obc` for the AVM (deterministic, capability-gated VM).

Design intent:

- Deterministic execution (agent-grade) with structured diagnostics.
- Capability-scoped effects (FS/NET/PROC/TIME/RNG/ENV).
- A path to compiler-in-AVM for sandboxed compilation.

Rolling policy: ABI and opcodes can change until an explicit stabilization
milestone is declared.

---

## Compiler pipeline (front-end and lowering)

Primary pipeline entry: `lib/compiler/compiler/040_build_pipeline.oren`.

Phases:

1) Parse + AST: `lib/compiler/lexer.oren`, `lib/compiler/parser_parse/*`.
2) Module linking + `@cfg` filtering: `lib/compiler/compiler/020_modules_linking.oren`.
3) Lowering passes (impls, traits, generics, sugar) under `lib/compiler/`.
4) Backend codegen (native / C / bytecode).

Evidence:

- Parser and diagnostics fixtures: `tests/native/fixtures/`.
- Module behavior: `tests/modules/`.

---

## Backend outputs

### C backend design and ABI

- Emits C and builds via a host toolchain (used for stage0 -> stage1).
- Entry: `lib/compiler/transpiler.oren` plus `lib/runtime.[ch]`.

### Native backend overview

- arm64: `lib/compiler/arm64_macho.oren`, `lib/compiler/arm64_elf.oren`.
- x64: `lib/compiler/x64_elf.oren`, `lib/compiler/x64_pe.oren`, `lib/compiler/x64_native_program.oren`.
- Runtime: `lib/runtime_native/` (syscall-first; avoid libc where practical).

Entry semantics (rolling): entry stub -> `native_runtime_init` -> `__top_level__` -> `main` (optional).
Tier-1 intent targets: `arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`.

Dynamic linking (rolling):

- macOS: Mach-O binding opcodes + GOT stubs.
- Linux: dynamic ELF + `dlsym` resolver when at least one `--link`/`@ffi.link` is present.
- Windows: lazy `LoadLibraryA`/`GetProcAddress` stubs.

Native tagged value representation is still converging; track gates in `docs/STATUS.md`.

### Native runtime layout

Native runtime layout details are enforced by the backend emitters and runtime
helpers (literal pools, entry stub init, and runtime globals). Use source and
fixtures as the ground truth: `lib/compiler/*` and `tests/native/fixtures/`.

### Native backend performance playbook

Key levers for hot paths:

- Inty propagation and lowerings that avoid runtime helpers.
- `LIST_INT` and typed buffer fast paths.
- Allocation fast paths (reuse, slabs).

Gates live in `docs/STATUS.md`.

### Native tagged value representation

Tagged value convergence is still rolling. The canonical model and migration
plan are tracked in `docs/STATUS.md`.

Tagged value convergence plan (rolling, lean):

- Current facts (rolling):
  - Native backend still has partial tagging; `oren_type_tag` is best-effort for scalars.
  - `nil`/`false`/`true` are runtime singleton values in native mode (not raw `0/1`).
  - AVM uses a tagged `AvmValue` representation (`lib/avm/avm.h`).
- OrenType tag map (v0, shared across backends):

| Tag | Name | Notes |
| --- | --- | --- |
| 0 | nil | canonical null |
| 1 | int | may also represent float in native v0 |
| 2 | float | defined in C/AVM |
| 3 | bool | `false`/`true` singletons |
| 4 | string | UTF‑8 bytes |
| 5 | py_obj | optional Python embedding |
| 6 | list | list + list<int> |
| 7 | map | deterministic ordered map |
| 8 | func | first‑class function values |
| 9 | u8_buf | typed buffer |
| 10 | i32_buf | typed buffer |
| 11 | i64_buf | typed buffer |
| 12 | f32_buf | typed buffer |
| 13 | f64_buf | typed buffer |
- Backend mapping (rolling):
  - C backend: `lib/runtime.h` `OrenType` enum is the source of truth.
  - AVM: `AvmType` differs internally, but `oren_type_tag` maps to OrenType tags
    (`AVM_VAL_LIST` and `AVM_VAL_LIST_INT` both map to tag 6).
  - Native: `oren_type_tag` is best‑effort for scalars; container/buffer tags match
    OrenType and list<int> reports tag 6 (list) until full tagging lands.
- Backend tag mapping table (rolling; `oren_type_tag` contract):

| OrenType tag | C backend (`lib/runtime.h`) | AVM (`lib/avm/avm.h`) | Native (`lib/runtime_native/130_printing.oren`) |
| --- | --- | --- | --- |
| 0 nil | `OREN_TYPE_NIL` | `AVM_VAL_NIL` | `native_value_is_nil` |
| 1 int | `OREN_TYPE_INT` | `AVM_VAL_INT` | best‑effort (scalars may report int) |
| 2 float | `OREN_TYPE_FLOAT` | `AVM_VAL_FLOAT` | may still report as tag 1 |
| 3 bool | `OREN_TYPE_BOOL` | `AVM_VAL_BOOL` | `native_value_is_false/true` |
| 4 string | `OREN_TYPE_STRING` | `AVM_VAL_STRING` | `oren_is_string` |
| 5 py_obj | `OREN_TYPE_PY_OBJ` | n/a | n/a |
| 6 list | `OREN_TYPE_LIST` | `AVM_VAL_LIST` + `AVM_VAL_LIST_INT` | `oren_is_list` + `oren_is_list_int` |
| 7 map | `OREN_TYPE_MAP` | `AVM_VAL_MAP` | `oren_is_map` |
| 8 func | `OREN_TYPE_FUNC` | `AVM_VAL_FUNC` | `oren_is_func` |
| 9 u8_buf | `OREN_TYPE_U8_BUF` | `AVM_VAL_BYTES` (u8 buffer) | `oren_is_u8_buf` |
| 10 i32_buf | `OREN_TYPE_I32_BUF` | `AVM_VAL_I32_BUF` | `oren_is_i32_buf` |
| 11 i64_buf | `OREN_TYPE_I64_BUF` | `AVM_VAL_I64_BUF` | `oren_is_i64_buf` |
| 12 f32_buf | `OREN_TYPE_F32_BUF` | `AVM_VAL_F32_BUF` | `oren_is_f32_buf` |
| 13 f64_buf | `OREN_TYPE_F64_BUF` | `AVM_VAL_F64_BUF` | `oren_is_f64_buf` |
- Define a single **canonical value model** that can be represented in:
  - native backend values,
  - C backend values,
  - AVM values (`AvmValue`).
- Pin the **semantic invariants** (truthiness, equality, type tests) and ensure
  every backend honors the same edge cases.
- Stage the migration with **compat shims** so fixtures remain valid during
  rollout (backend-by-backend switches).
- Add a fixture gate that asserts the **same observed behavior** across
  native/C/OBC for representative mixed‑type programs.
  - Fixtures must cover: truthiness, equality, type tags/names, container access,
    and optional/dynamic value handling.
  - Gate: parity fixtures + `make test` green on Tier‑1.

### Bytecode backend (OBC)

- Compiler: `lib/compiler/codegen_bytecode/`.
- VM: `lib/avm/`.
- Output: `.obc` with constant pool + opcode stream.

---

## Runtime and stdlib layering

Layering model (rolling):

1) Intrinsics: compiler/runtime-known primitives (string/list ops, alloc hooks).
2) Builtin syslib: minimal shipped modules used by the toolchain (strings, bytes, math).
3) Shipped stdlib: network, crypto, codecs, etc.
4) Third-party libs.

Constraints:

- Syscall-first for native runtime (no libc dependency for core services).
- Deterministic behavior for AVM and capability-scoped effects.

Evidence:

- Runtime behavior: `tests/native/test_*` and fixtures under `tests/native/fixtures/`.
- Networking + TLS loopback gates: `tests/native/test_tls_loopback.oren`,
  `tests/native/test_https_get_loopback.oren`, `tests/native/test_wss_echo_loopback.oren`.

### TLS provider availability

TLS is OS-dependent. Providers today live under `lib/std/net/`:

- macOS: SecureTransport.
- Linux: OpenSSL.
- Windows: Schannel/SSPI.

When a provider is not implemented on a target, `tls.*` helpers return a structured error.

### UI v0 schema (headless core)

Headless UI core is under `lib/std/ui/` with a JSON-like command schema used by
`std:ui/commands`. See `tests/avm/test_ui_*` for fixtures.

---

## AVM and OBC (bootstrap spec summary)

### Value model (rolling)

- `AvmValue` tagged union (`lib/avm/avm.h`).
- Stack-based VM (`lib/avm/avm_vm.c`).
- Heap: currently `malloc` for heap objects (no GC yet).
- `LIST_INT` is an unboxed int64 list fast-path for tight loops.

### OBC wire format (today)

- Header: magic `0x0ECD`.
- Const count: `u16` little-endian.
- Constant pool:
  - `0`: NIL
  - `1`: INT (`u64` little-endian)
  - `2`: BOOL (`u8`)
  - `3`: FLOAT (`u64` float64 bit pattern)
  - `4`: STRING (`u16` length + bytes)
  - `8`: BYTES (`u32` length + bytes)
- Code: byte stream of 8-bit opcodes + operands.

Rolling metadata conventions (unused BYTES constants appended by compiler):

- `OREN_META\n1\n` + JSON metadata (same structure as native `--metadata`).
- `OREN_OBX\n1\n` + binary export/reloc table used by the linker.
- `OREN_SIG\n1\n` + ed25519 signature over a canonical hash (optional enforcement).

### Capability model (rolling)

- Effects are grouped by domains (FS/NET/PROC/ENV/TIME/RNG).
- AVM can enforce domain allow-lists before execution.

Evidence:

- AVM smoke and determinism fixtures: `tests/avm/`.

### AVM concurrency model (deterministic, syscall-first, aligned multiverse-friendly)

AVM runs single-threaded today. Deterministic scheduling and explicit budgeting
remain rolling work items tracked in `docs/STATUS.md`.

### AVM NEON mapping plan (arm64, no-JIT-first)

SIMD in AVM is gated and must remain deterministic. Tracking and coverage live
in `docs/STATUS.md`.

### AVM in AVM multiverse design (nested virtual universes)

Nested AVM execution is supported behind capability gating (Domain AVM). The
direction is deterministic, budgeted child universes with virtualized effects
and snapshot/restore semantics. Track in `docs/STATUS.md`.

---

## Performance levers (rolling)

Hot-loop parity depends on compiler + runtime cooperation:

- Inty propagation and lowering to native arithmetic fast paths.
- Typed buffers and SIMD kernels (native + AVM).
- AVM TMP freelist (env-gated) for short-lived allocations.
- AVM list/list_int freelist (env-gated) for list payload churn.

---

## Region / arena allocation plan (rolling)

Goal: reduce GC overhead in hot loops by allocating short‑lived objects in a
resettable arena instead of the GC heap.

Constraints:

- Preserve determinism and safety (no use‑after‑free; no hidden lifetime extension).
- Work under current native runtime model (`oren_find_node` checks + list magic).
- Keep behavior identical across backends unless explicitly gated.

Hot‑path selection (rolling):

- Auto mode targets syntactic `while`/`for` loops that allocate list/list_int in the loop body.
- Heuristics stay conservative: skip complex control flow or uncertain escapes.
- Explicit opt‑in/out annotations are supported: `@oren.arena` forces evaluation for
  a loop, `@oren.arena_iter` forces per‑iteration push/pop, and `@oren.noarena`
  disables auto wrapping for that loop.

Proposed compiler strategy (first slice):

1) Escape analysis for loop‑local allocations (lists + list<int>):
   - Only adopt arena for allocations that do not escape the loop body
     (not returned, not stored in globals, not captured by closures).
2) Lowering:
   - Insert `arena_push()` at loop entry and `arena_pop()` at loop exit.
   - Replace `oren_new_list` / `oren_new_list_int` + grow paths with
     `arena_new_list` / `arena_new_list_int` (same layout; arena‑backed buffers).
3) Fallback to GC heap when analysis is uncertain.
4) Rolling auto‑mode (`OREN_ARENA_AUTO_LOOP=1`):
  - Wraps simple loops and rewrites loop‑local list allocations only when usage
    stays in safe list intrinsics (conservative escape check).
  - Rewrites only **unconditional top‑level** `var`/`assign` list allocations in the loop
    body (no conditional/nested rewrites).
  - List literals (empty or non‑empty) are expanded to arena alloc + ordered pushes.
  - `OREN_ARENA_PER_ITER=1` switches auto‑mode to per‑iteration push/pop instead of
    loop‑scoped arenas (helps long‑lived loops).
  - Heuristic: loops without a simple literal upper bound (e.g., `i < 1000`) default
    to per‑iteration mode to prevent unbounded arena growth. A const‑int bound stored
    in a prior local (`var n = 1000; while i < n`) is also treated as bounded if the
    bound is not reassigned inside the loop.
   - Requires the allocation to **dominate first use** in the loop body
     (use‑before‑assign skips rewriting).
   - Only wraps loops without `break`/`return`/`continue` in the same loop body
     (nested-loop `continue` does not block the outer loop).
   - When wrapped, `break`/`return`/`continue` in the same loop body get a pre‑exit
     `arena_pop`; `continue` is allowed for `while` and `for` (post runs after pop).

Runtime design (native):

- Arena allocates raw pages via `sys_mmap_private_anon`, with a bump pointer.
- `arena_push()` records a mark; `arena_pop()` rewinds the bump pointer and
  invalidates arena tracking for that generation.
- Arena objects must still be classified by `oren_find_node` so list operations
  remain safe. This requires a **separate arena tracking table**:
  - entries map `ptr -> {kind, gen}` (not GC‑managed).
  - on `arena_pop`, bump a generation counter and reset the table (lazily
    ignore stale generations to avoid per‑iteration clears).

Non‑goals (initial slice):

- Cross‑thread arenas or shared ownership.
- Replacing GC for long‑lived objects.
- Arena support for maps/structs until list paths are stable.

Long‑lived loop policy (hybrid):

- Prefer **per‑iteration sub‑arenas** when escape analysis proves values do not
  cross iteration boundaries (safe to reset each iteration).
- Any value that escapes the iteration (stored in outer scope, returned, or
  captured) must allocate in the GC heap or an outer long‑lived arena; the
  loop arena is reserved for iteration‑local temps.
- Otherwise use a **loop‑scoped arena with budgets**: enforce `OREN_ARENA_CAP_BYTES`
  and spill to GC once the cap is reached.
- For non‑terminating loops, **epoch rotation** reclaims arena pages at safe points
  (spilled allocations remain in GC).

Tracking/gates:

- `alloc_churn`/`alloc_drop` should show near‑zero GC activity for arena‑eligible loops.
- Keep `make test` and Tier‑1 parity fixtures green.
- List<int> dot loops: consider an i32-range guard + SIMD dot kernel (accumulating in i64) to
  unlock NEON/SSE2 parity without changing language semantics.
- Allocation fast paths (small object slabs, reuse).

The weighted performance tracker and gates live in `docs/STATUS.md`.

---

## Toolchain + Platforms (build, verify, portability)

### Bootstrapping (stage0 -> stage2)

Prereqs: Go 1.20+, a C compiler, and `make`.

Canonical fast path:

```bash
make bootstrap   # stage0 Go compiler
make            # stage1 self-hosted compiler
make stage2     # stage2 self-host
```

Notes (rolling):

- `make stage2` is the repo-supported entrypoint because the bootstrap backend can vary by host.
  - Default: Stage 2 is bootstrapped via the native backend on Tier-1 hosts.
  - Use the legacy C-backend bootstrap if needed: `make stage2 OREN_STAGE2_BACKEND=c`.
- Windows hosts default to MSVC `cl.exe` for C-backend builds. Stage0 and stage1 auto-configure
  MSVC via `vswhere.exe` and `VsDevCmd.bat` / `vcvars64.bat` when `--cc` is not provided.
  - Overrides: `OREN_MSVC_VSWHERE`, `OREN_MSVC_INSTALL_PATH`, `OREN_MSVC_DEV_CMD`.
  - One-off MSVC commands: `scripts/win_msvc_cmd.cmd <cmd> ...`.

### Building programs

```bash
./oren build your_prog.oren --backend {c|native|bytecode} -o build/your_prog
```

- `--platform <arch>-<os>` (or `OREN_PLATFORM`) selects the target; default is host.
- Default outputs when `-o/--out` is omitted:
  - `build/targets/<arch>-<os>/<backend>/<basename>` (native/c)
  - `build/targets/<arch>-windows/<backend>/<basename>.exe` (native/c, Windows)
  - `build/targets/avm/bytecode/<basename>.obc` (bytecode)

When using `--emit-c`, avoid generating `*.oren.c` next to sources. Keep emitted C under
`build/` (or a temp dir) to prevent Makefile implicit-rule coupling.

### Build caches (performance-critical)

- Build cache (default on): `build/cache` (override `--cache-dir` / `OREN_CACHE_DIR`, disable `OREN_NO_CACHE=1`).
- Native runtime AST cache (native backend):
  - disable: `OREN_NATIVE_RUNTIME_ASTBIN_CACHE=0`
  - override dir: `OREN_NATIVE_RUNTIME_ASTBIN_CACHE_DIR=<dir>`
  - seed dir: `OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR=<dir>` (use `make astbin-seed`)
- Native runtime object cache (native backend, Tier-1 throughput):
  - disable: `OREN_NATIVE_RUNTIME_OBJ_CACHE=0`
  - override dir: `OREN_NATIVE_RUNTIME_OBJ_CACHE_DIR=<dir>`
  - seed dir: `OREN_NATIVE_RUNTIME_OBJ_SEED_DIR=<dir>` (use `make rtobj-seed`)

### Verification (fast path)

Local (fast):

- `make test`
- `make verify-native-quick`
- `make test-native-all`

Cross-arch Tier-1 matrix (when touching native/runtime/net):

- `./scripts/verify_native_matrix.sh`
- `./scripts/verify_native_net_matrix.sh`
- `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win`
- `./scripts/verify_stage0_windows_bootstrap.sh`

Local x64-linux execution (QEMU in the Linux container):

- `make verify-x64-linux-qemu`
- optional: `make verify-x64-linux-qemu-net`, `make verify-x64-linux-qemu-tls`

### Remote x64 workflow (Win11 + WSL2 optional)

The x64 Tier-1 gates run on a remote Windows 11 host (WSL2 optional) via the scripts above.
Prefer using the scripts; they own the copy/run logic and logging.

Notes (rolling):

- Remote staging uses `G:\work` by default (C: is often full on the host).
- Logs are stored under `project-doc/remote/<timestamp>/...`.
- If the default host/proxy is unreachable, override via the script flags/env (see script headers).

### Portability + `@cfg`

Rules of thumb:

- Keep `@cfg` at the boundary; tests should share a core and hide platform glue behind tiny `@cfg` wrappers.
- Prefer portable stdlib APIs over per-file `@cfg` where possible.
- Use `@cfg` primarily for FFI bindings, constants, and syscall layout differences.

### AVM tooling

`./avm` includes disassembly and trace tooling. Run `./avm --help` for the current CLI surface.

### CLI completion

Shell completion is generated by the compiler:

- `oren completion bash`
- `oren completion zsh`

One-shot activation:

```bash
source <(oren completion bash)
```

```zsh
source <(oren completion zsh)
```

---

## Canonical references

- Entry point: `docs/README.md`
- Language manual + spec: `docs/LANGUAGE.md`
- Status, tracker, feature matrix: `docs/STATUS.md`
- Sources of truth: `tests/` and `lib/`
