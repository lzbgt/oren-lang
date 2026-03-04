# Structured Error Model (Rolling)

Last updated: 2026-03-05

Status: Design (rolling). This is a proposal intended to align cross-backend behavior.

## Goals

- Provide a **recoverable error flow** for expected failures (I/O, parse, bounds, etc.).
- Preserve **determinism and cross-backend parity** (C/native/bytecode).
- Keep the model **cheap** in hot paths (no mandatory stack unwinding).
- Be **incremental**: adoptable by stdlib and user code without breaking rolling builds.

## Non-goals (for v0)

- A full exception system with stack unwinding.
- Typed algebraic error types baked into the compiler.
- ABI-stable error layouts across FFI boundaries.

## Existing primitives (facts today)

- `oren_err(code, msg)` returns an error value.
- `oren_is_err(v)` checks whether a value is an error.
- `oren_err_code(v)` and `oren_err_msg(v)` extract code/message.
- `std:result` provides helpers (`is_err`, `is_ok`, `unwrap`, `expect`, `ok_or_errno`).
- Many stdlib functions already return `oren_err(...)` on invalid inputs.

These primitives are already used by the compiler toolchain and stdlib; the design
formalizes their behavior and usage.

## Proposed model (v0)

### 1) Result-style convention (value-or-error)

Functions that can fail return either:

- a **normal value** (success), or
- a **structured error value** (failure).

The error value is created by `oren_err(code, msg)` and detected by `oren_is_err`.
No special control-flow is implied; errors are ordinary values until explicitly handled.

### 2) Standard error shape

`std:result` assumes the error value is a map-like object with at least:

- `code` (int)
- `msg` (string)
- `__err` (true)

This is not a hard ABI promise yet, but the runtime + stdlib already behave
as if this is true. We should keep that convention consistent across backends.

### 3) Syscall adapters (errno -> error)

Low-level syscall-style APIs return `rc` where:

- `rc >= 0` => success
- `rc < 0`  => `-errno`

`std:result.ok_or_errno(rc, ctx)` converts this into the structured error value.
This pattern is already used; the design makes it the official adapter.

### 4) Error handling helpers (stdlib)

Standard helpers (already present in `std:result`) are the preferred way to
handle errors:

- `unwrap(v)` / `expect(v, msg)` for fail-fast control paths.
- `unwrap_or(v, default)` for best-effort flows.
- `ok_or_errno(rc, ctx)` for syscall adapters.

These helpers should remain pure, deterministic, and cross-backend compatible.

## Proposed language sugar (later, optional)

This is **not** required for v0, but could be added once the convention is stable:

- `try expr` sugar that returns the error early if `expr` is an error.
- `catch` blocks for local recovery.

The sugar should lower to plain value-or-error checks so it remains backend-neutral.

## Migration plan (rolling)

1) **Document and stabilize** the error convention (this doc + `docs/LANGUAGE.md`).
2) **Audit stdlib** and ensure functions either:
   - return structured errors, or
   - document explicit panic behavior.
3) **Add fixtures**:
   - A small `std:result` smoke that validates `ok_or_errno`, `unwrap`, and `expect`.
4) **Gradual adoption**:
   - Convert a few high-signal stdlib modules (e.g., `std:list`, `std:buffer`) to
     use the convention consistently.

## Open questions

- Should error values carry optional context fields (e.g., `path`, `op`)?
- Do we need a small set of **stable error codes** (e.g., invalid arg, not found)?
- How should errors be rendered in diagnostics and test output?

## Acceptance criteria (v0)

- The convention is documented in `docs/LANGUAGE.md`.
- At least one stdlib module and one fixture validate the error helpers.
- No backend-specific divergence in `oren_err` or `oren_is_err` semantics.
