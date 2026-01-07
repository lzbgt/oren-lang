# Active Tracker (Rolling)

**Last updated:** 2026-01-07

This repo is in rolling mode. This file tracks the **highest-priority active work** in execution order,
plus the **regression gates** that must stay green.

Long-form notes and completed items live in `docs/TODOS_ARCHIVE.md`.

## How to use this tracker

- **Pick work:** start at **P0 (Now)** and take the first unfinished item that unblocks Tier‑1
  parity/perf.
- **When an item is “done enough” (rolling):**
  - put the detailed write-up in `docs/TODOS_ARCHIVE.md`
  - keep a short “baseline status” note + the regression gate here
- **Don’t fight the size:** this file can be ~300 lines if needed, but use `<details>` blocks to keep
  the default view scan-friendly.

Legend:

- Priority: **P0 (Now)** > **P1 (Soon)**
- Size tags: **(S/M/L)** = expected engineering scope (not difficulty)
- Tier‑1 host/targets intent: `arm64-macos`, `arm64-linux`, `x64-windows`, `x64-linux` (WSL2 counts as
  the Tier‑1 x64-linux execution host today)

## Regression gates (run first when touching compiler/runtime)

Local (fast):

- `make test` (native quick integration smoke; fast default)
- `make verify-native-quick` (stage1 + stage2 native smoke)

Cross-arch matrix (execution on real hosts):

- `./scripts/verify_native_matrix.sh` (native quick across local + docker + remote x64)
- `./scripts/verify_native_net_matrix.sh` (TCP/UDP/HTTP loopback + WebSocket; stage1 + stage2; all Tier‑1)
- `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` (compiler runs on x64 hosts and compiles+runs a tiny program)
- `./scripts/verify_stage0_windows_bootstrap.sh` (stage0→stage1 via MSVC on Win11; stage1 builds+runs a tiny native program)

Local x64 sanity (compile-only):

- `make verify-native-x64-compile` (stage1 + stage2 emit x64-linux + x64-windows)

References:

- Perf playbook: `docs/NATIVE_BACKEND_PERF_PLAYBOOK.md`
- Remote x64 workflow: `docs/REMOTE_X64_ENV.md`

## P0 (Now)

0) **Toolchain resource bounds (self-hosting + tests)** (L)

   - Keep these paths reliable and bounded:
     - `make verify-native-quick` (stage1 + stage2 native smoke)
     - `make test-native-all` (native suite; stage1)
     - `make verify` (stage1 → stage2 self-hosting gate)

   - Hard gates (non-negotiable for rolling):
     - Stage2/Stage3 self-host compiler build stays **< 3 minutes** wall time (primary dev host).
     - Stage2 native backend “compile one file” (rtobj hit; non-capsule) stays **< 4s** wall time.
     - Debug builds used by Tier‑1 fixtures stay **< 10s** per `oren build ... --backend native --debug` step (default script timeout).
     - RSS stays **< 300 MB** for the compilation process.

   - High-leverage direction (avoid “parameter tuning”):
     - avoid O(n²) string/collection patterns in compiler-side tooling (include expansion, C backend transpiler, whole-program passes)
     - deterministic parallel compilation pipeline (module graph scheduling + cache hits)
     - eliminate global/shared mutable state that prevents safe parallelism (or centralize it behind explicit concurrency primitives)
     - reduce compiler heap churn by moving hot internal data away from pointer-heavy `map/list` graphs:
       - prefer typed buffers (`u8_buf`) + compact encodings for AST/IR/module artifacts (e.g. `astbin` / CBOR-like) when crossing worker boundaries or caching
       - keep the in-process “fast path” zero-copy where possible (shared-memory attach instead of returning large graphs through `join`)

   - Active focus (current perf gap):
     - stage2-native rtobj-miss (cold) path is still too slow due to runtime bundle decode + runtime decl compilation
     - target: **< 10s** cold “compile one file” when caches are empty (see `docs/TODOS_ARCHIVE.md` for current measurements + profiling knobs)

<details>
<summary>P0.0 context: recent performance work + measurements</summary>

- Recent completions are tracked in `docs/TODOS_ARCHIVE.md` (keep this list focused on what’s next).

- New (2026-01-06): x86_64 cross-target self-host compiler builds are now bounded (no multi-minute stalls in single backend helper functions); details in `docs/TODOS_ARCHIVE.md`.

- Remaining (active): rtobj-miss (cold) path is still too slow in stage2-native due to runtime bundle decode + runtime decl compilation; keep pushing toward **< 10s** cold “compile one file” when caches are empty (see `docs/TODOS_ARCHIVE.md` for current measurements + profiling knobs; current is ~`15s` on arm64-macos stage2 for `examples/hello.oren` in `./scripts/bench_native_compile_one_file.sh --no-debug` run-1 (isolated rtobj dir; seed disabled)).
  - New (2026-01-05): introduced a smaller “core” native runtime entry (`lib/runtime_native_core.oren`) selectable via `OREN_NATIVE_RUNTIME_PROFILE=core` so cold rtobj misses can be bounded for typical programs without removing the full runtime surface (default remains `lib/runtime_native.oren`).
    - Seed support: `scripts/build_runtime_astbin_seed.sh` now seeds full+core+capsule runtime astbins; `scripts/build_rtobj_seed.sh` supports `--runtime-profile` (or env `OREN_NATIVE_RUNTIME_PROFILE`) without pruning other profiles' seeds.
    - Fixed (2026-01-06): build cache key now hashes the effective injected native runtime entry (full vs core), so switching `OREN_NATIVE_RUNTIME_PROFILE` cannot reuse cached artifacts built with a different runtime (details in `docs/TODOS_ARCHIVE.md`).

  - Recent (2026-01-04): x86_64 cross-target cold miss is still expensive when the rtobj seed is disabled, but it is materially improved by:
    - eliminating per-instruction allocations in the x64 encoder (`lib/compiler/x64_core.oren`)
    - keeping capsule enforcement implementation out of the non-capsule runtime rtobj (`lib/runtime_native/035_capsule_stubs.oren`)
    - simplifying runtime decl hotspots to reduce stage2-native decl compile work (`oren_iter_next`, `oren_bytes_from_string_ptr`, `oren_int_to_string`), plus using `iadd`/shifts in byte loops to avoid slow generic `+`/`*` lowering (details in `docs/TODOS_ARCHIVE.md`)
      - Recent (2026-01-05): x64 intrinsic temp spill slots are now addressed via compiler-internal `IntrTmp{idx}` nodes + a per-function base-offset reservation (`ctx["intr_tmp_base_off"]`), eliminating `$tmp_intrN` identifier strings and per-function locals-map inserts in stage2-native rtobj builds.
      - Fixed (2026-01-06): x64 intrinsic-temp spill allocator now reserves slot 0 (1-based indices) to avoid stage2-native `nil==0` collisions that could silently skip call/arg lowering (e.g. “print disappears” / missing string literals); regression gate added to `scripts/verify_native_x64_compile_only.sh` (details in `docs/TODOS_ARCHIVE.md`).
    - Recent (2026-01-04): native runtime `oren_string_from_bytes` restored a fast list-backed-buffer copy path (keeps lexer/tooling bounded); u8_buf continues to use the slice helper fast memcpy path.
    - Note (regression prevention): compiler-side helpers must remain portable across stage1 (C runtime) and stage2 (native runtime); avoid using `ptr_*` byte loads on “string” values unless explicitly guarded.
    - Next: continue shrinking the rtobj decl bucket by refactoring remaining large native-runtime helpers (recent top decls include `oren_string_from_bytes` and `oren_net_get`; prefer direct buffer access and `iadd`/shift arithmetic in loops).
    - stage2 `--platform x64-linux` true miss (isolated rtobj dir; `OREN_NATIVE_RUNTIME_OBJ_SEED_DIR=0`, astbin seed enabled): rtobj `total_ms` ~`17–18s` (`parse_ms` ~`1.8s`, `decls_ms` ~`14.0s`), with `OREN_TRACE_X64_RT_OBJ_SUMMARY=1`.
    - same build with rtobj seed enabled (empty cache dir; seed-hit): ~`5.3s` total (see `make rtobj-seed-x64`).

  - Capsule note (resolved): stage2-native “cold parse” of `lib/runtime_native_capsule.oren` can be tens of seconds if the runtime astbin cache is empty; this is now mitigated by the runtime-astbin seed (`make astbin-seed`, `OREN_NATIVE_RUNTIME_ASTBIN_SEED_DIR`) so cold capsule builds can stay under the default 10s timeout in typical dev setups.

  - Current miss breakdown (arm64-macos; stage2; `OREN_TRACE_ARM64_RT_OBJ_SUMMARY=1`, seed disabled):
    - runtime astbin decode/parse: ~`2.1s` total (astbin v2 decode ~`1.3s`)
    - runtime decl compile: ~`7.0s`
    - finalize: ~`1.4s`
    - rtobj meta encode (astbin v2): ~`1.1s`
    - rtobj build+apply total: ~`12.8–13.0s` (overall compile-one-file miss: ~`15.2–15.3s`)

  - Decl bucket drill-down (arm64-macos; stage2; `OREN_TRACE_ARM64_RT_OBJ_TOP_DECLS=1`):
    - The decl bucket is mostly real per-decl compilation work (sum of decl compile times ~= decls_ms).
    - Current “top decls” include (approx): `_oren_map_set_kind_unchecked` (~`839ms`), `native_capsule_proc_match_token` (~`386ms`), `oren_avm_run_obc_bytes` (~`224ms`), `native_capsule_fs_mount_resolve` (~`221ms`), `oren_sha256_range` (~`143ms`).
    - High-leverage direction: reduce what the compiler needs to inject/compile (tooling/runtime layering or a DCE/reachability model for rtobj), so cold rtobj builds don’t compile large AVM/HPC/capsule surfaces unnecessarily.

  - Recent (2026-01-04): default `lib/runtime_native.oren` no longer includes the syscall-hook-only capsule modules (`050_capsule_fs_hooks`, `070_capsule_net_hooks`), reducing runtime decl count (rtobj `decls_n`) in non-capsule builds; capsule builds use `lib/runtime_native_capsule.oren`.

</details>

1) **Tier‑1 native support parity (`arm64-macos`, `arm64-linux`, `x64-linux`, `x64-windows`)** (L)

   - Keep native semantics aligned across platforms:
     - callables/closures/varargs + deterministic failure modes (`OREN_DIAG` + stack traces)
     - container ops (list/map/buf) with identical semantics across arch/OS
     - concurrency primitives on Windows (no fork assumptions): `spawn`, `oren_join(_timeout)`, and a path to cooperative cancellation

   - Regression gates:
     - native matrix: `./scripts/verify_native_matrix.sh`
     - NET loopback matrix: `./scripts/verify_native_net_matrix.sh`
     - x64 self-host compiler run: `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win`
     - Windows stage0→stage1 bootstrap: `./scripts/verify_stage0_windows_bootstrap.sh`

   - Active gaps (keep this list forward-looking; details live in `docs/TODOS_ARCHIVE.md`):
     - Build system parity (Windows host):
       - Done: Makefile now emits `.exe` outputs on Windows (`oren.exe`, `oren_stage2.exe`, `avm.exe`) and the local smoke/seed scripts under `scripts/` recognize Windows (`MINGW*`/`MSYS*`/`CYGWIN*`) and suffix temporary artifacts with `.exe`.
       - Done: Windows-host bootstrap defaults now reliably select MSVC `cl.exe` when `OREN_BOOTSTRAP_CC` is not set (fixes `make test` / `make stage1` under Git Bash/MSYS2).
       - Intent: `make`, `make test`, `make stage2`, `make verify-native-quick` should work under MSYS2/Git Bash/Cygwin (stage0 still uses MSVC `cl.exe`, auto-configured by stage0; see `docs/REMOTE_X64_ENV.md`).
     - NET stdlib maturity:
       - Current: `lib/std/net/http.oren` supports HTTP/1.1 GET over TCP (Content-Length + chunked; IPv4-only; no TLS/keep-alive pooling yet).
         - Hostname URLs are supported via DNS A lookup (explicit resolver injection; best-effort system default on POSIX only).
       - Done: portable `SO_KEEPALIVE` + `std:net/tcp.set_keepalive(fd, enable)` (syscall-first; translated across Darwin/Linux/Windows).
         - Regression: `tests/native/test_net_suite.oren` now asserts `sys_setsockopt(... SO_KEEPALIVE ...)` succeeds (covered by `./scripts/verify_native_net_matrix.sh`).
       - Done: UDP `recvfrom` can capture the source sockaddr (src ip/port) via `oren_udp_recvfrom_into_with_addr`.
         - Regression: `tests/native/test_net_suite.oren` `test_udp_loopback` asserts the source port matches the sender’s bound port (covered by `./scripts/verify_native_net_matrix.sh`).
       - Done: TCP `TCP_NODELAY` exposed as `OREN_TCP_NODELAY` + `std:net/tcp.set_nodelay(fd, enable)`.
         - Regression: `tests/native/test_net_suite.oren` asserts `sys_setsockopt(level=IPPROTO_TCP, optname=TCP_NODELAY)` succeeds (covered by `./scripts/verify_native_net_matrix.sh`).
       - Done: DNS v0 loopback A-query client (`std:net/dns.query_a`) + best-effort default resolver selection on POSIX.
         - Default resolver selection: `dns.default_resolver` reads `OREN_DNS_SERVER`, else parses `/etc/resolv.conf` (IPv4 only; no Windows resolver yet).
         - HTTP hostname support: `http.get_text_resolver(url, timeout_ms, resolver)` accepts an explicit `dns.resolver(...)` config (offline/deterministic tests).
         - Regression: `tests/native/test_dns_loopback.oren` (stage1 + stage2; all Tier‑1 via `./scripts/verify_native_net_matrix.sh`).
         - Regression: `tests/native/test_http_get_loopback.oren` now also covers hostname URLs via a loopback DNS server (stage1 + stage2; all Tier‑1).
       - Next: structured HTTP client/server surface (headers map + status + streaming body), then production WebSocket:
         - fragmentation + binary frames + streaming recv API
         - TLS in stdlib (HTTPS + WSS) + then HTTP/2 framing + system resolver (Windows DNS APIs + AAAA; POSIX `resolv.conf` AAAA support)
     - Native FFI / dynamic linking parity (rolling):
       - Done (linux x64 + arm64): dynamic ELF (`PT_INTERP` + `PT_DYNAMIC`) + `DT_NEEDED` + minimal `.rela.dyn` (GLOB_DAT-style relocations) so `ffi` works via a `dlsym` resolver.
       - Next: fuller ELF PLT/JMPREL story for direct imports (optional), and shared library output parity (`--lib` / `.so` / `.dll`).
     - Conditional compilation for cross-platform stdlib (rolling):
       - Done: `@cfg(...)` (canonical `@oren.cfg`) filters declarations by target `--platform` (`os`/`arch`/`platform` selectors).
       - Regression: `tests/native/cfg_os_select.oren` is compiled in `scripts/verify_native_x64_compile_only.sh` (stage1 + stage2; x64-linux + x64-windows).
       - Implementation note: use byte-wise string equality in compiler passes (see `docs/IMPLEMENTATION_NOTES.md` section 9) so behavior matches in stage1 (C runtime) and stage2 (native runtime).
     - Shared library output parity (native `--lib`/`--shared`):
       - Remaining: x86_64 ELF `.so` and x86_64 Windows `.dll` emission (exports + metadata/header hooks).
     - Concurrency substrate convergence:
       - POSIX: replace fork-based `spawn` substrate with real OS threads + shared-memory sync, plus a GC/safepoint model that remains correct once true threads exist.
     - Windows PROC story:
       - Keep the cross-OS PROC surface coherent (pid/kill/wait semantics or define a cross-OS `sys_spawn` boundary).

<details>
<summary>P0.1 context: recent Tier‑1 bring-up fixes (baseline notes)</summary>

- Fixed (2026-01-07): x86_64 self-host compiler run gate (Win11 + WSL2) now passes; keep this as a hard regression gate:
  - `./scripts/verify_selfhost_x64_compiler.sh --targets x64-wsl,x64-win` (details in `docs/TODOS_ARCHIVE.md`)
  - Also proves host auto-detection (remote runs omit `--platform` and rely on runtime host detection / `OREN_PLATFORM` fallback).

- Fixed (2026-01-07): stage0 (Go bootstrap) can build stage1 on **x64-windows** using VS2022 `cl.exe`, and the resulting stage1 binary can run on Windows (stack-safe entrypoint).
  - Regression gate: `./scripts/verify_stage0_windows_bootstrap.sh` (details in `docs/TODOS_ARCHIVE.md`).

- Fixed (2026-01-07): Tier‑1 NET loopback is now regression-gated across `arm64-macos` + `arm64-linux` + `x64-windows` + `x64-linux` (stage1 + stage2) via `./scripts/verify_native_net_matrix.sh`.
- Fixed (2026-01-07): WebSocket v0 (ws:// handshake + masked text frames + loopback echo) implemented and added to the Tier‑1 NET matrix (`tests/native/test_ws_echo_loopback.oren`).
- Fixed (2026-01-07): portable OS entropy surface for protocols:
  - `oren_getentropy(ptr,len)` (native runtime) backed by `getentropy` (macOS) / `getrandom` (Linux) / `BCryptGenRandom` (Win11)
  - `std:crypto/rand` used by WebSocket client key + masking (no more time-seeded xorshift in stdlib)
  - Capsule: `oren_getentropy` is gated by `@cap.requires(domain="RNG")` (allow via `--cap-allow-domains RNG` / `OREN_CAP_ALLOW_DOMAINS=...`).
  - Fixed (2026-01-07): Win11 WS echo loopback flake eliminated by hardening NET read/write against spurious readiness timeouts (optimistic `recv`/`send` first; retry until deadline instead of returning `ETIMEDOUT` immediately).
  - Fixed (2026-01-07): ping/pong/close frames are handled in `ws.recv_text` (auto-pong + ignore pongs), and `ws.send_ping_{client,server}` exists.
  - Fixed (2026-01-07): client key + masking use OS entropy (`oren_getentropy`), not time-seeded xorshift.

- Fixed (2026-01-04): **arm64-macos stage2 is now bootstrapped via the native backend by default** (`make stage2`).
  - Fallback (bring-up): `make stage2 OREN_STAGE2_BACKEND=c`.

- Native FFI / dynamic linking parity (rolling):
  - Current reality:
    - **macOS (Mach‑O):** `ffi` works via dyld binding opcodes + `--link` dylibs.
    - **Windows x64 (PE):** `ffi` works via lazy `LoadLibraryA`/`GetProcAddress` stubs; `--link` supplies DLL search names/paths (kernel32 searched by default).
    - **Linux (ELF):**
      - **x64-linux:** `--link` enables dynamic linking; `ffi` works via a lazy `dlsym(RTLD_DEFAULT, "...")` resolver (remote WSL2 gate).
      - **arm64-linux:** `--link` enables dynamic linking; `ffi` works via a lazy `dlsym(RTLD_DEFAULT, "...")` resolver (docker linux/arm64 gate).
  - Regression gates (current):
    - Remote Win11: `scripts/verify_native_matrix.sh --targets x64-win` runs `tests/native/ffi_windows_kernel32.oren` (stage1 + stage2).
    - Local sanity: `make verify-native-x64-compile` compiles Windows FFI examples (including `--link msvcrt.dll` propagation checks).
    - Linux contracts (native backends):
      - Panic (arm64-linux + x64-linux without `--link`): `scripts/verify_native_matrix.sh` runs `tests/native/ffi_linux_unresolved_panics.oren` and asserts `ffi unresolved:` + `oren_panic`.
      - OK (arm64-linux with `--link`): `scripts/verify_native_matrix.sh --targets arm64-linux` runs `tests/native/ffi_linux_strlen_ok.oren` (stage1 + stage2; docker container).
      - OK (x64-linux with `--link`): `scripts/verify_native_matrix.sh --targets x64-wsl` runs `tests/native/ffi_linux_strlen_ok.oren` (stage1 + stage2; remote WSL2).

- Windows: complete a coherent PROC story (pid/kill/wait semantics or define a cross-OS `sys_spawn` boundary).
  - Fixed (2026-01-04): `oren_system(_timeout)` now works on `x64-windows` (CreateProcessA path).
    - Tier‑1 fixture no longer soft-skips Windows.
    - Native quick integration now includes a Windows-only `oren_system_timeout(...)` smoke to prevent regressions.
    - Runtime object cache key now includes a backend signature so codegen changes invalidate cached runtime machine code.

- Recent cross-arch hardening (details in `docs/TODOS_ARCHIVE.md`):
  - x86_64 stack traces resolve symbols under rtobj cache mode on Win11 (Tier‑1).
  - arm64 debug stack traces symbolize runtime frames under rtobj cache mode.
  - x86_64 varargs+spread no longer recurse inside `__oren_fnwrap_*` (Win11 Tier‑1).
  - x86_64-linux WSL2 `oren_select` hang fixed via `epoll_event` ABI probing.
  - native runtime `for x in view` yields typed-buffer view elements (slice/stride/matrix protocol).
  - matrix scripts retry remote `scp` uploads (proxy flake hardening).

</details>

2) **Determinism + replay (native + AVM)** (L)
   - MANTIS requires deterministic replay and traceability (`mantis.md` “Observability & reproducibility”).
   - AVM has deterministic TIME/RNG + record/replay fixtures today; native needs an equivalent “deterministic mode” story:
     - record/replay boundary for effectful ops (FS/NET/PROC/ENV/TIME/RNG)
     - deterministic scheduling option (ties into structured concurrency)
   - Reference goal doc: `OREN_MANTIS_STDLIB_GOALS.md`

3) **Native value tagging (remove “key kind inference” fragility)** (L)
   - Goal: maps do not require explicit key kind in the language model; the runtime can safely decide based on tagged values.
   - Keep tightening interim safety rules:
     - container ops must never dereference untracked values
     - key-kind inference must not rely on numeric-range heuristics
   - Deliverable: a native value representation that can distinguish:
     - immediates (ints/bools/nil) vs pointers
     - string/list/map/buf payload kinds
   - References:
     - `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md`
     - `docs/DESIGN_CONTAINER_OPS.md`

4) **Backend architecture unification (CoreIR boundary)** (L)
   - Make one canonical CoreIR own semantics (eval order, short-circuit, varargs packing, closure ABI).
   - Backends become thin adapters (ABI + emit).
   - Rolling progress: extracted native stmt→ops lowering + expr validation to a shared module (`lib/compiler/native_ops_v0.oren`) to reduce backend drift and prep for deeper unification.
   - References:
     - `docs/BACKEND_ARCHITECTURE.md`
     - `docs/IR_AND_COMPILER_INTERNALS.md`

5) **Container ops as operations (no hot-path stdlib overhead)** (M)
   - Ensure `xs[i]`, `xs[i]=v`, `len`, `push` lower to intrinsics where appropriate.
   - Make map/list/buf iteration semantics deterministic across backends (add a unified iterator protocol so `for x in buf` works identically on arm64/x86_64 and across native/C/AVM).
   - References:
     - `docs/DESIGN_CONTAINER_OPS.md`
     - `docs/STDLIB_LAYERS.md`

6) **AVM in AVM + compiler-in-AVM (deterministic toolchain in a capsule)** (M)
   - Make `.oren → .obc` compilation runnable inside AVM with budgets and locked capability surfaces.
   - References:
     - `docs/AVM_MULTIVERSE.md`
     - `docs/AVM_SPEC_V1.md`
     - `docs/SELF_HOSTING.md`

7) **Stdlib distribution + module resolution (native + AVM)** (M)
   - One coherent story for end users:
     - `import ... "std:foo"` resolution
     - source vs precompiled stdlib bundles
     - AVM consuming the same stdlib without host-FS assumptions
   - References:
     - `docs/STDLIB_RESOLUTION_AND_DISTRIBUTION.md`
     - `docs/OBC_MODULE_LINKING.md`

8) **HPC/SIMD parity (arm64 NEON today; x86_64 SSE2/AVX next)** (M)
   - Keep determinism contract: scalar is authoritative; SIMD must be bit-identical for covered kernels.
   - Expand x86_64 SIMD coverage once x64 native reaches semantic parity.
   - References:
     - `docs/HPC_SERVER_PLAN.md`
     - `docs/AVM_NEON_MAPPING_PLAN.md`

9) **Tooling (modern compiler UX; self-hosting behind gates)** (M)
   - Keep Go bootstrap canonical until Oren-native tooling meets reliability/perf gates.
   - Track Oren-native tools as gated milestones: `fmt`, `test`, `pkg`, `lsp`.
   - References:
     - `docs/TEST_SYSTEM.md`
     - `docs/CLI_COMPLETION.md`
     - `docs/SELF_HOSTING.md`

10) **Tests & iteration speed (integration-first; backend/arch neutral by default)** (S)
   - Keep `make test` (native quick smoke) iteration-fast and deterministic.
   - Prefer a small number of high-signal integration suites + fixtures as living spec.
   - Cross-arch: `./scripts/verify_native_matrix.sh` has opt-in Tier‑1 fixture targets (`x64-win-tier1`, `x64-wsl-tier1`) in addition to the fast quick-integration matrix.
   - Perf regression playbook (native backend): `docs/NATIVE_BACKEND_PERF_PLAYBOOK.md`
   - Lightweight tripwire (rtobj hit): `make perf-guard-native-hit` (or `./scripts/perf_guard_native_compile_one_file_hit.sh`)
   - Keep tests hermetic: avoid relying on host shells or external utilities (prefer helper binaries built from Oren sources + explicit `oren_proc_spawn`).
   - Keep tests OS-neutral: avoid asserting platform `struct stat` layouts; prefer Oren-owned stable ABIs (e.g. OrenStatV0 via `oren_stat_alloc()`).
   - Make test tooling robust in minimal environments too: avoid relying on host shells/utilities in test programs.
   - Reference: `docs/TEST_SYSTEM.md`

## P1 (Soon)

1) **Signed `.obc` + root trust (multiverse updates / “app store”)** (M)
   - Formalize cert chain constraints and root pubkey distribution/rotation.
   - Keep private keys out of repo (`../oren-ca/`).
   - References:
     - `docs/APPSTORE_ROOTCA_AND_UPDATES.md`
     - `docs/CERT_CHAIN_FORMAT.md`

2) **Stackless recursion beyond TCO (heap call frames)** (L)
   - For non-tail recursion that cannot be optimized by TCO, provide a deterministic heap-frame model (AVM-like).
   - Reference: `docs/STACK_SAFETY.md`

3) **Native scheduler + netpoller (IO readiness → channels + select)** (L)
   - Keep `select` channel-based at the language surface; fd readiness integrates by producing channel events.
   - Already exists (today, in code/tests): `oren_select` / `oren_select_recv` runtime APIs (native + AVM), plus fd readiness waits (`oren_fd_wait_{readable,writable}` etc).
     - Not done yet: language-level `select { ... }` syntax, and a native green-thread scheduler/netpoller that wakes channels instead of blocking the whole process/thread.
   - Bring native closer to AVM semantics:
     - mature channels beyond pipe-based bring-up
     - deterministic fairness rules where practical (round-robin cursor)
     - structured cancellation/timeouts
   - OS backends (planned):
     - macOS: kqueue/kevent + ulock parking
     - Linux: epoll (or io_uring later) + futex-like parking
     - Windows: IOCP for sockets (WinSock `select` is not sufficient for general async IO); unify with PROC/FS strategy
   - References:
     - `docs/CONCURRENCY_MODEL.md`
     - `docs/NATIVE_GMP_SCHEDULER.md`
     - `docs/ASYNC_IO_AND_SELECT.md`

4) **Portable core + reflective types + value repr refactor** (L)
   - Goal (rolling, allowed to break compatibility): make Oren’s internal “unsafe core” small, fast, and portable, and make types first-class with reflection as a primary design constraint.
   - Deliverables (design → implementation):
     - define a portable core runtime layer for unsafe primitives:
       - string buf / array buf (contiguous, amortized growth, explicit capacity)
       - IO ops surface (file + fd + basic NET) with explicit error codes
     - make types first-class and reflective:
       - stable “type object” representation
       - reflective APIs for field layout / method tables / generic instantiations (as designed)
     - redesign the native value representation (reduce “64-byte OrenValue” storage inefficiency):
       - unify with the native tagged-value plan and remove key-kind inference fragility as a side-effect
   - References:
     - `docs/TYPE_SYSTEM_PLAN.md`
     - `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md`
     - `docs/STDLIB_LAYERS.md`
