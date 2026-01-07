# WebSocket (stdlib, native backend) — v0

This doc tracks the current “v0” WebSocket support in Oren’s stdlib, implemented on top of the syscall‑first `NET` substrate.

## Status

- **Implementation:** `lib/std/net/ws.oren`
- **Evidence / regression gate:** `tests/native/test_ws_echo_loopback.oren`, executed by `scripts/verify_native_net_matrix.sh` across Tier‑1:
  - `arm64-macos` (local)
  - `arm64-linux` (docker container)
  - `x64-windows` (remote Win11)
  - `x64-linux` (remote WSL2)

## API (v0)

All functions are timeout‑bounded to avoid hangs.

- `ws.connect(url, timeout_ms)` → `{"ok":1,"fd":int}` or `{"ok":0,"err":string}`
- `ws.accept(listen_fd, timeout_ms)` → `{"ok":1,"fd":int}` or `{"ok":0,"err":string}`
- `ws.send_text_client(fd, text, timeout_ms)` → `0` on success, or `-errno`
  - Client frames are **masked** (required by RFC6455).
- `ws.send_text_server(fd, text, timeout_ms)` → `0` on success, or `-errno`
  - Server frames are **unmasked**.
- `ws.send_ping_client(fd, payload, timeout_ms)` → `0` on success, or `-errno`
- `ws.send_ping_server(fd, payload, timeout_ms)` → `0` on success, or `-errno`
- `ws.recv_text(fd, timeout_ms)` → `{"ok":1,"v":string}` or `{"ok":0,"err":string}`
  - v0.1 behavior: internally handles **ping/pong/close** frames (auto-pong + ignore pongs).

## Scope / limitations (v0)

This is intentionally minimal so we can gate correctness across Tier‑1 first.

- URL: `ws://<ipv4>[:port][/path]` only
  - no DNS
  - no TLS (`wss://`)
- Frames:
  - **text frames only** (opcode=1)
  - no fragmentation support
  - payload size is capped (currently 1 MiB) as a rolling safety bound
- Handshake:
  - `Sec-WebSocket-Accept` computed via `SHA1(key + GUID)` then base64
  - client key + masking use OS entropy via `std:crypto/rand` (`oren_getentropy`), not time-seeded toy RNG

## Native runtime caveat: string tracking vs `+`

In the native runtime, string `+` concatenation is **kind‑gated** (implemented by `oren_add`).

- If either operand is not tracked as kind=STRING, `+` behaves like integer add.
- For protocol code, this is dangerous: accidental pointer arithmetic can produce invalid pointers and crash on the next byte load.

Practical rule:

- If you create a string from raw bytes/pointers in stdlib (e.g. header slices), allocate it as a tracked STRING (`malloc_k(..., kind=1)`) or intern it (`oren_intern_cstr(...)`) before using `+`.

## Testing & stress knobs

The Tier‑1 loopback regression is designed to stay bounded and avoid huge logs, while still being able to reproduce intermittent issues.

- `OREN_WS_ECHO_N=<n>`: run the handshake + one text echo **n** times in a single process run of `tests/native/test_ws_echo_loopback.oren` (default: `1`).
  - This is useful for reproducing rare flakes (e.g. WinSock readiness edge cases) without adding verbose tracing.
  - `scripts/verify_native_net_matrix.sh` propagates this env var to the docker container + remote Win11/WSL2 runs when set in the caller environment.

Win11 note:

- WinSock `select()` can occasionally report a timeout even when data becomes readable/writable shortly after (observed during Tier‑1 bring-up).
- The native NET runtime now treats readiness waits as advisory: it tries `recv`/`send` first and, on a reported timeout, retries until the caller deadline is actually exhausted.
