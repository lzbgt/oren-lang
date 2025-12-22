# Stdlib Resolution & Distribution (Compiler + AVM)

This document proposes a **user-friendly stdlib import model** (no `../../lib/std/...` prefixes)
and a distribution story that works for:

- native and C backends (`oren build ...`)
- bytecode backend (`.obc`)
- AVM execution (running `.obc`)
- future “compiler inside AVM” (compile source to `.obc` inside a sandboxed universe)

It is written against the **current** compiler behavior in this repo:

- `import name "path"` stores a string path (parser: `lib/compiler/parser_parse/030_tail.oren`).
- module loading currently resolves paths relative to importing file (linker: `lib/compiler/compiler/020_modules_linking.oren`).

---

## 1) Problem statement

Today, end-user code typically imports stdlib like:

```oren
import math "../../lib/std/math.oren"
```

This is:

- not user-friendly,
- not stable under project layout changes,
- hard to distribute (the path assumes the repo layout),
- awkward for AVM/capsule environments where host paths should be irrelevant.

We want:

- stable logical imports: `import math "std:math"` or `import json "std/json"`,
- predictable deterministic resolution,
- a packaging story for shipping the stdlib to end users.

---

## 2) Design goals

1) **Ergonomics**
   - Users should never need `../../...` to import the stdlib.

2) **Deterministic builds**
   - Given a source tree + stdlib content, import resolution should be stable.

3) **No silent name collisions**
   - Local modules should not accidentally shadow stdlib modules without an explicit choice.

4) **AVM compatibility**
   - The same source should compile outside AVM and inside AVM if the stdlib is present in the universe.

5) **Rolling evolution**
   - This repo is rolling; we can change the import resolver and docs without preserving old behavior forever.

---

## 3) Proposed import specifiers

Oren keeps the existing grammar:

```
import_stmt = "import" ident string_lit [ ";" ] ;
```

We interpret the string literal as a **module specifier** (not necessarily a filesystem path).

### 3.1 Stdlib specifiers (recommended)

Two equivalent forms:

- `std:` scheme form:
  - `import math "std:math"`
  - `import common "std:linalg/common"`
- `std/` path form:
  - `import math "std/math"`
  - `import common "std/linalg/common"`

Rules:
- `.oren` extension is optional: `"std/json"` resolves to `std/json.oren`.
- Nested modules map to subdirectories: `"std/linalg/common"` resolves to `lib/std/linalg/common.oren` in the repo layout.

### 3.2 Filesystem specifiers (existing behavior)

- Relative paths: resolved relative to the importing file directory.
- Absolute paths: allowed.

We also support extensionless filesystem imports for convenience:
- `"foo/bar"` resolves to `"foo/bar.oren"` if the last segment has no `.`.

---

## 4) Resolution algorithm (compiler)

### 4.1 Stdlib root discovery

The compiler needs a stable way to find the stdlib source root (`STDLIB_ROOT`).

Current implementation (rolling, pragmatic):

Priority order:

1) `OREN_STDLIB_ROOT` environment variable
   - If it points directly at the stdlib directory, use it.
   - If it points at an install/repo root, accept `<root>/lib/std`.

2) Walk up from the importing file directory looking for `lib/std/argparse.oren`
   - Works for repo development and for projects vendoring the compiler tree.

3) Fallback: `lib/std` relative to the current working directory

This makes development “just work”, and gives packagers a single knob (`OREN_STDLIB_ROOT`)
for installed distributions.

### 4.2 Import resolution

Given `(base_dir, specifier)`:

- If `specifier` starts with `std:` or `std/`:
  - resolve to `STDLIB_ROOT/<specifier_rest>`
  - append `.oren` if needed
- Else:
  - resolve to `<base_dir>/<specifier>`
  - append `.oren` if needed

---

## 5) Distribution models (end users)

There are two realistic distribution strategies. Both can coexist.

### Model A: Ship stdlib sources alongside the compiler (recommended now)

Installer layout (example):

```
<install_root>/
  bin/oren
  lib/std/...
```

Then:
- set `OREN_STDLIB_ROOT=<install_root>/lib/std` in the wrapper script / environment.

Pros:
- simple,
- transparent (users can inspect stdlib),
- easy to patch/override for rolling development.

Cons:
- requires a multi-file install.

### Model B: Embed stdlib sources into the compiler (future)

The compiler binary (native or `.obc`) contains a “stdlib pack” (e.g. a compressed blob).
At compile time it can:

- mount the pack as a virtual filesystem, or
- unpack it into a temporary directory, or
- serve sources from memory to the parser.

Pros:
- single-file distribution,
- perfect for “compiler inside AVM” (no host FS dependency).

Cons:
- more engineering: packaging, compression, versioning, potential size concerns.

---

## 6) AVM interaction (important clarification)

### Running `.obc` programs in AVM

If a user program is already compiled to `.obc`, the AVM does **not** need the stdlib sources.
All imports are resolved at compile time and linked into the output program/module graph.

### Compiling inside AVM (future “inception” track)

If we want “source → `.obc` inside AVM”, the compiler running in AVM needs access to stdlib sources.
That can be provided by:

- mounting the stdlib tree into the AVM VirtualFS at a known location,
- setting `OREN_STDLIB_ROOT` inside the universe environment,
- or using Model B (embedded stdlib pack).

This integrates cleanly with capability-based constraints:
- stdlib reads come from VirtualFS (not host FS),
- deterministic snapshots can hash the stdlib pack + user source.

---

## 7) Open questions / next steps

1) Add a formal “module search path” list (like `OREN_PATH`) for non-stdlib packages.
2) Add a standard “vendor” directory layout (`vendor/<pkg>/...`) for reproducible builds.
3) Decide whether stdlib is versioned with the compiler or independently.
4) Add oretest audits ensuring docs/examples do not regress to `../../lib/std/...`.

