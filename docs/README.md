# Oren Documentation

**Last updated:** 2026-05-26

This is the canonical entry point for current Oren documentation. It intentionally
keeps only facts that match the current implementation and points historical or
experimental notes to focused files.

## What Oren Is

Oren is a self-hosted language and compiler with three backend paths:

- **C backend**: portable bootstrap path through a host C compiler.
- **Native backend**: direct Mach-O/ELF/PE output; arm64 macOS is the most mature surface.
- **Bytecode backend**: emits `.obc` bytecode for AVM, the deterministic capability-gated VM.

The project is still in rolling mode. ABI/opcode stability, full native tagged-value
convergence, AVM production embedding, and full Tier-1 platform maturity are not
declared stable yet.

## Fast Navigation

- Current readiness and priorities: `docs/STATUS.md`
- Language manual and current semantics: `docs/LANGUAGE.md`
- Compiler/runtime/backend design map: `docs/DESIGN.md`
- Active TODOs: `TODOS.md`
- AVM iOS readiness inspection: `project-doc/ios_avm_readiness_20260507.md`
- Generated HTML docs site: `docs/site/index.html`

## Common Commands

```bash
./oretest
./oretest --selfhost
make
make test
make test-curated
make avm
make test-avm
make docs-site
```

`./oretest` is the preferred local entry point. `make test` maps to the fast native
smoke path; use `make test-curated` for the broader capability/backend/surface bundle.

## Build Examples

```bash
# C backend
./oren build examples/hello.oren --backend c -o build/hello_c

# Native backend
./oren build examples/hello.oren --backend native -o build/hello_native

# Bytecode / AVM
./oren build examples/hello.oren --backend bytecode -o build/hello.obc
./avm build/hello.obc
```

## Current Backend Reality

- **C backend** is the portability/bootstrap baseline.
- **Native backend** is fastest-moving; arm64 macOS has the strongest verification history.
- **AVM/OBC** has deterministic execution, capability gates, budgets, VFS/VPROC/VNET
  fixture surfaces, snapshots, and coroutine/generator fixtures, but remains below
  production embedding maturity.
- **Compiler-in-AVM** exists as fixture/bootstrap work, not as a packaged production
  pipeline.

## Documentation Policy

Keep `docs/` concise and current. Put dated investigation evidence in `project-doc/`
only when it remains actionable. Avoid re-adding large rolling logs to canonical docs;
use build logs for raw evidence and summarize only the retained conclusion.
