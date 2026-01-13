# Portability Guide (Rolling): when to use `@cfg`

Oren’s goal is **portable source code** across Tier‑1 targets:

- `arm64-macos`
- `arm64-linux`
- `x64-linux`
- `x64-windows`

The language provides `@cfg(...)` conditional compilation (see `docs/LANGUAGE_MANUAL.md` and
`docs/LANGUAGE_SPEC.md`), but in a production language it should be treated as a **boundary tool**:

- good: isolate unavoidable OS differences behind a stable API
- bad: sprinkle `@cfg` throughout application logic

This document gives concrete rules for *where `@cfg` belongs* in Oren code and tests.

## 1) Rule of thumb

Use `@cfg(...)` only when **the surface you must call does not exist** on another Tier‑1 OS/arch, or
when the ABI/layout is truly platform-specific.

If the code is “regular logic” (parsing, maps/lists, formatting, protocol logic), do **not** use `@cfg`:
push the OS differences into stdlib or into a tiny shim module.

## 2) Prefer stdlib portability over per-file `@cfg`

### Prefer portable APIs

Examples of portable APIs (Tier‑1 intent):

- `std:net/tcp`, `std:net/udp`, `std:net/dns` (network sockets + resolver)
- `std:net/tls` (TLS over sockets)
- `std:crypto/*` (PEM, rand, TLS core helpers)
- `std:ui/*` (retained-mode UI core: layout/render/raster; OS integration is a shim)

If you need to `@cfg` around a commonly-used concept, that is usually a signal that the stdlib is
missing a “portable core + per-platform backend” split.

### Example pattern: portable API + `@cfg` backend selection

The recommended shape is:

- one portable module exports the public API
- per-platform modules implement the OS-specific pieces and are `@cfg`-gated
- consumers import only the portable module

Sketch:

```oren
// std:crypto/tls_provider (portable surface)
fn tls_client_connect(...) {
    return _tls_client_connect_impl(...)
}

@cfg(os="windows") fn _tls_client_connect_impl(...) { return schannel_connect(...) }
@cfg(os="macos")   fn _tls_client_connect_impl(...) { return securetransport_connect(...) }
@cfg(os="linux")   fn _tls_client_connect_impl(...) { return openssl_connect(...) }
```

The key constraint is: the public API should remain stable; only the private implementation changes.

## 3) FFI: avoid `@cfg` by using portable aliases when available

If the intent is “call libc”, do not write three variants:

```oren
@cfg(os="linux")  @ffi.link("libc.so.6") ffi { ... }
@cfg(os="macos")  @ffi.link("libSystem.B.dylib") ffi { ... }
@cfg(os="windows") @ffi.dll("msvcrt.dll") ffi { ... }
```

Prefer:

```oren
@ffi.libc
ffi { /* ... */ }
```

Notes:

- `@ffi.libc` is the portability mechanism; it keeps library naming out of user code.
- Use `@cfg` for FFI only when there is **no** portable alias and the ABI truly differs.

## 4) Tests/fixtures: keep `@cfg` at the boundary

Tier‑1 fixtures are part of the “living spec”. They should be:

- small
- deterministic
- **portable**

If a fixture needs platform glue, the preferred approach is:

1) keep the core test logic portable (protocol logic, state machines, invariants)
2) gate only the platform-specific declarations:
   - FFI imports / DLL names (if no alias exists)
   - syscall struct layouts
   - OS-only behavior knobs required to run the test safely

Bad pattern (hard to maintain):

- `@cfg` inside core logic branches for “how the algorithm works”.

Good pattern:

- `@cfg` is used only to select *how to access the same abstract capability* on each platform.

### Why fixtures sometimes still use `@cfg`

Some subsystems legitimately have different host constraints:

- TLS providers differ per OS (SChannel / SecureTransport / OpenSSL)
- process spawning APIs differ (Win32 CreateProcess vs POSIX fork/exec)
- UI needs OS windowing APIs (Win32/X11/Cocoa)

The correctness requirement is: those differences must be hidden behind a stable userland API, and the
portable logic (including protocol semantics) should not fork into per-OS variants.

## 5) When `@cfg` is unavoidable

Use `@cfg` when:

- you are writing a thin OS bridge (syscalls, windowing, IOCP/epoll/kqueue)
- the ABI layout or calling convention differs (FFI return kinds, struct packing)
- you are binding to an OS-owned subsystem where “portable emulation” would be incorrect or unsafe

In those cases:

- keep the `@cfg` module small
- keep the stable API above it strict and well-tested
- add a Tier‑1 gate so regressions are caught early

