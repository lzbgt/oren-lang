# Examples (Rolling, Kept Relevant)

This folder contains runnable examples that exercise **integrated** Oren features:

- C backend (portable)
- native backend (Tier‑1 intent: arm64 + x86_64)
- bytecode backend + AVM (determinism, capsules, multiverse)

The canonical “examples suite” is:

```bash
make examples-test
```

## Key examples

- `examples/hello.oren`
  - Minimal “hello” that also exercises: `std:list`, `std:iter`, closures, `for x in ...`.
  - Used by: `make examples-test` (native + bytecode).

- `examples/gc_test.oren`
  - Native GC smoke (allocations + `native_gc_collect()` + validation).
  - Used by: `make examples-test`.

- `examples/module_app.oren` + `examples/modules/math.oren`
  - Demonstrates file-module imports and `std:math`.

- `examples/ffi_test.oren`, `examples/libmath.oren`, `examples/ffi_from_libmath.oren`
  - Demonstrate macOS native FFI, dylib export/header generation, and `oren scan`.

- `examples/avm_vfs_demo.oren`, `examples/avm_vproc_demo.oren`, `examples/avm_vnet_demo.oren`
  - Demonstrate AVM capability domains and virtual backends (no host effects).

- `examples/avm_multiverse_net_demo.oren` + `examples/avm_fixtures/multiverse_child_net.oren`
  - Demonstrate AVM-in-AVM (“multiverse”) + VirtualNET fixtures.


## Architecture review support

These examples are useful when evaluating deterministic runtime behavior, capability boundaries, native/bytecode backend tradeoffs, and agent-safe execution surfaces. For a paid review of how this kind of runtime design maps to your own agent infrastructure, use Agent-C:

- Ask first: https://x2.brucelu.top/products/contact/?offer=agentc&source=github-oren-examples
- Sample review: https://x2.brucelu.top/agent-c/sample/
- Checkout: https://x2.brucelu.top/agent-c/checkout/?source=github-oren-examples

Boundary: paid support is architecture review and setup guidance, not guaranteed production deployment or managed runtime operation.

## Running notes

- Linux ELF and Windows PE artifacts are not runnable on macOS hosts.
  - Use a Linux machine or the Win11+WSL2 remote workflow: `docs/DESIGN.md`.

