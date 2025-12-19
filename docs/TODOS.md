# TODOs (Execution Order, Rolling)

This repo is in **rolling ABI** mode. This file is intentionally short (about 5–10 items): it is the execution order for the next engineering work.

- Completed / detailed history: `docs/TODOS_ARCHIVE.md`
- Platform focus right now: **macOS arm64 first** (but avoid designs that block Linux arm64 later).

## Rules (Enforced For Every Task)

These are “project laws”. If a task can’t follow these, we *change the task design*.

1) **No hangs (timeouts everywhere)** `[safety]`
   - Test/build steps must never block forever.
   - Any new long-running subprocess must be wrapped in a wall-time timeout.

2) **No libc shims / no libc dependency** `[arch]`
   - Native backend output must not require `libc` facilities like `malloc/free`, `pthread`, `stdio`.
   - Runtime must be implemented via `sys_*` primitives + `.oren` code.

3) **No build-time dependency on host SDK/system headers** `[arch]`
   - OS ABI constants live in repo-owned tables (`lib/compiler/*_abi_*.oren`).
   - System headers are audit-only and may be vendored under `docs/refs/*` for verification.

4) **Syscall-first enforcement is mandatory** `[safety]`
   - Raw syscalls must be centralized and gated (capsule pre/post hooks stay authoritative).
   - No bypassing capsule capability checks by emitting direct `svc` / OS sysno calls outside the approved lowering modules.

5) **Verify before declaring done** `[quality]`
   - Canonical curated suite (preferred): `./oretest --target macos`
   - Wrapper (same suite): `make test`

6) **Keep this file actionable** `[maint]`
   - Each P0/P1 item must have a concrete “Definition of Done” (DoD) and be finishable.
   - Avoid “infinite P0s” like “harden everything” without a crisp deliverable.
   - Keep the list 5–10 items total; merge and delete aggressively.

7) **Linux Docker runner is persistent** `[maint]`
   - Use a long-lived linux/arm64 container for smoke tests (avoid `docker run --rm` + repeated installs).
   - Prefer reusing `OREN_DOCKER_NAME=oren-linux-dev` and restarting it when needed to refresh bind mounts.

## Tasks (Next, Highest Priority First)

1) **P0 [vm] AVM v1 foundation: capability-governed host interface + determinism** `[safety]`
   - DoD: AVM supports the v1 direction (see `docs/AVM_SPEC_V1.md`) in a way that enables agentic execution:
     - capability domains (FS/NET/PROC/ENV/TIME) as explicit ops
     - deterministic TIME/RNG, snapshot/resume, multiverse
   - Next deliverable: scheduling + determinism tightening:
     - time-sliced cooperative tasks (gas quantum; deterministic)
     - `join_timeout` semantics in deterministic TIME
     - `select` fairness rules + send cases (not only recv)

2) **P1 [arch] Traits/protocols: move from syntax to meaning** `[lang]`
   - DoD: trait/impl has real compile-time meaning without runtime vtables.
   - Next deliverables (in order):
     - compile-time ambiguity diagnostics for multiple impls of the same `Type.method`
     - (design) optional explicit qualification syntax for disambiguation (keep deterministic)

3) **P1 [stdlib] Oren-native AVM as builtin syslib component** `[arch]`
   - DoD: AVM can be built (later: rewritten) in `.oren` as part of the toolchain stdlib (`docs/STDLIB_LAYERS.md`).
   - Next deliverable: define the minimal “AVM-in-Oren” surface area (hosted by C AVM first).

4) **P1 [boot] Oren compiler as an AVM feature** `[arch]`
   - DoD: AVM can ingest `.oren`, compile to `.obc`, and run it in a child universe (no JIT; service-side JIT later).
   - Next deliverable: design the in-memory compilation pipeline + sandboxed module loader rules.

5) **P2 [maint] Capsule safety hardening (keep, but don't derail roadmap)** `[safety]`
   - DoD: syscall-first capsule enforcement stays airtight while language/AVM evolve.
   - Next deliverable: keep static audits + a small curated runtime fixture suite for each domain.

## Recently Completed (high signal)

- `make test` is curated + timeout-safe via `./oretest` (parallel module/AVM runs, prints logs only on failures).
- Call-site spread `...` implemented across C/native/bytecode (for variadic builtins + apply-style calls, without committing to a stable varargs ABI).
- Rolling type-annotation sugar: universal `name: Type` metadata (`u8/u16be/f64/...`) + packed-struct views via `pack_view`.
- `enum` + `match` sugar implemented; `match` stays contextual (identifiers named `match` are valid).
- `docs/OBJECT_MODEL.md` clarified: primitives can implement traits; static-first deterministic dispatch.
- Linux: AVM builds cleanly in docker (fixed `fread` result handling + `int64_t` formatting warning).
- Language: `trait` and `impl Trait for Type { ... }` syntax accepted by parser; impl methods lower deterministically into plain `fn`s (bootstrap-friendly).
- Language: method-call sugar resolver:
  - `x.method(a, b)` resolves (with `x: Type` in scope) to the lowered impl function `__oren_impl__...__method(x, a, b)`
  - `Type.method(a, b)` resolves to the lowered impl function `__oren_impl__...__method(a, b)`
- AVM bytecode backend: cooperative concurrency MVP:
  - `spawn`/`oren_join` supported (VM-internal tasks; deterministic; no host syscalls)
  - `oren_new_channel` / `oren_chan_send` / `oren_chan_recv` / `oren_select_recv` supported
