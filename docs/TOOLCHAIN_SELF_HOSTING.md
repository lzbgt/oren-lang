# Toolchain Self‑Hosting (Status + Gate Plan)

This doc answers a recurring question in rolling mode:

> “Is the Oren compiler mature enough to self-host the entire tool system (tests, fmt, LSP, package manager, source + `.obc` distribution)?”

## Current state (facts in this repo)

Oren is already **partially self-hosting**:

- **Stage 1 compiler** `./oren` is built by the **Go bootstrap** `./oren_bootstrap` (`make stage1`).
- **Stage 2 compiler** `./oren_stage2` is built by **Stage 1** (`make stage2`).
  - Rolling default: `make stage2` bootstraps stage2 via the **native backend** on arm64‑macOS.
  - Bring‑up fallback: `make stage2 OREN_STAGE2_BACKEND=c`.
- The **metadata tool** is **Go**: `./oredoc` (`cmd/oredoc`).
- The **signing tool** is **Go**: `./orensign` (`cmd/orensign`).
- The **AVM interpreter** is **C**: `./avm` (sources under `lib/avm/`).

So today, the compiler can compile itself (stage2), but the repo toolchain is still a **mixed bootstrap stack**:

```
Go: oren_bootstrap / oredoc / orensign
Oren: oren / oren_stage2 (compiler)
C: avm (VM)
```

This is consistent with the roadmap stance in `docs/ROADMAP.md`: keep bootstrapping practical until language + runtime contracts stabilize.

## What “full self-hosted toolchain” actually requires

Self-hosting the compiler *itself* is a narrower bar than self-hosting “tooling”:

### A) `oren fmt` (formatter)

Minimum requirements:

- A stable **parser** that can round-trip with enough syntax metadata to preserve intent (comments, whitespace, string literal forms, etc), or a deliberate “canonical formatting” policy.
- A stable **AST** representation (internal is fine) and output printer with deterministic emission.

Formatter is usually the **first** tool worth self-hosting because it can be:

- offline
- deterministic
- not latency-sensitive like an LSP

### B) `oren lsp` (language server)

LSP is the hardest to self-host early because it benefits from:

- **error recovery** parsing (must build partial ASTs on invalid code)
- **incremental** analysis (document edits, file watchers, caches)
- semantic indexing (symbol tables across modules)
- stable JSON-RPC IO and concurrency primitives

Today we can build an LSP sooner by:

1) keeping the server in Go (fast iteration) and invoking `./oren` as a library/process, or
2) exporting a stable machine interface (`oren --emit-json ast|diag|symbols`) and writing the LSP around that.

Self-hosting the LSP in Oren becomes realistic once:

- module resolution rules are stable
- compiler diagnostics are stable and machine-readable
- stdlib has robust FS/process/JSON IO on macOS/Linux/Windows

### C) Oren-native test runner (future)

Right now the repo runs tests via **direct compilation + direct execution** of test programs using `./oren` and `./oren_stage2` (see `docs/TEST_SYSTEM.md`).
There is no external test runner binary in-tree; the canonical flows are `Makefile` targets and `scripts/` helpers (for example `scripts/verify_native_matrix.sh` for remote x86_64 verification).

A self-hosted replacement would require:

- a stable `tests/manifest` format (or `tests/*.oren` conventions)
- stable process spawning + timeouts + log capture
- cross-platform file operations

This is very achievable later, but it should be **gated** (see below) so we don’t regress reliability during rolling refactors.

### D) Package manager (source + `.obc`)

A real package manager requires more than “downloading some files”:

- **Module identity**: name, version, and provenance (git URL or registry ID)
- **Reproducibility**: lockfile pinned revisions + hashes
- **Caching**: build cache keyed by (compiler version, target, flags, package hash)
- **Distribution**:
  - source distribution (build locally)
  - `.obc` distribution (precompiled bytecode for AVM execution)
  - optionally native artifacts (per-OS/arch)

If the end-goal includes AVM multiverse updates and signed modules, the package manager needs to integrate with the trust model in:

- `docs/AVM_AND_OBC.md`
- `docs/CERT_CHAIN_FORMAT.md`
- `docs/CODESIGN.md`

In other words: the package manager is also a **supply chain system**, not just a convenience.

## Is Oren “mature enough” today?

### Compiler self-hosting: **yes, gated**

We already build Stage 2 from Stage 1, which is the key “compiler can compile itself” milestone.

But “no Go anywhere” is **not** true today, because Stage 0 and key tools are still Go.

### Toolchain self-hosting: **not yet (but can start in slices)**

The fastest way to reach a production-grade toolchain without stalling compiler work is:

1) Keep the current Go tools as “production runners” (stable, cross-platform),
2) Add **Oren-native prototypes** behind explicit gates,
3) Promote them only when they meet strict reliability/perf criteria.

## Gate plan (recommended)

Treat self-hosting as a staged migration with explicit acceptance tests:

1) **Gate 0 (today)**: Go bootstrap + Go repo tooling is canonical; Oren compiler evolves quickly.
2) **Gate 1 (fmt)**: add `oren fmt` (even if it only supports a stable subset first).
3) **Gate 2 (pkg)**: add `oren pkg` with:
   - local path deps + git deps (pinned)
   - lockfile
   - cache dir conventions
   - optional signing hooks (`orensign`) for `.obc`
4) **Gate 3 (test runner)**: Oren-native runner that can execute a curated manifest, with hard timeouts.
5) **Gate 4 (LSP)**: only after error-recovery parsing + stable diagnostics + module graph caching exist.

Each gate should include:

- correctness suite (native backend + AVM + cross-platform where applicable)
- determinism checks (stable outputs)
- cross-platform checks (macOS + Linux + Windows, x64+arm64 where applicable)

## Connection to `oren-packages`

Even if a “packages repo” exists, a package manager needs a **spec**:

- package manifest format (name/version/deps/targets)
- dependency resolution rules
- build artifact layout and caching keys
- signature and verification metadata for `.obc`/OBX (if used)

Until those are specified, a packages repo is useful mainly as:

- a place to host canonical libraries
- a testbed for module resolution rules

Once the spec exists, the repo can become a real registry mirror or a git-based index.
