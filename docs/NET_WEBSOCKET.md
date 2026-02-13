# WebSocket (stdlib, native backend) — v0

This doc tracks the current “v0” WebSocket support in Oren’s stdlib, implemented on top of the syscall‑first `NET` substrate.

## Status

- **Implementation:** `lib/std/net/ws.oren`
- **Evidence / regression gate:** `tests/native/test_ws_echo_loopback.oren`, executed by `scripts/verify_native_net_matrix.sh` across Tier‑1:
  - `arm64-macos` (local)
  - `arm64-linux` (docker container)
  - `x64-windows` (remote Win11)
  - `x64-linux` (remote WSL2)

Last verification (fact):

- 2026-01-10: `make verify-native-net-skip-remote` passed on:
  - `arm64-macos` (local)
  - `arm64-linux` (docker container `c7e5f7bd9f5c`)
- 2026-01-10: `make verify-x64-linux-qemu-tls` passed on:
  - `x64-linux` under QEMU in docker container `c7e5f7bd9f5c` (stage1 + stage2; includes WSS loopback)
- `x64-linux` / `x64-windows` runs require the remote Win11 (WSL2 optional) host; see `docs/REMOTE_X64_ENV.md` if the proxy/hostname is unavailable.

## API (v0)

All functions are timeout‑bounded to avoid hangs.

- `ws.connect(url, timeout_ms)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
- `ws.connect_resolver(url, timeout_ms, resolver)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
- `ws.connect_resolver_opts(url, timeout_ms, resolver, opts)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
  - `opts["tls"]` is passed to `tls.wrap_client` for `wss://` URLs (see `docs/NET_TLS.md`).
  - `resolver` is a config map returned by `std:net/dns.resolver(server_ip, server_port, timeout_ms)`
  - Use this to keep hostname behavior deterministic in tests (loopback DNS server), or to avoid relying on `/etc/resolv.conf`.
- `ws.accept(listen_fd, timeout_ms)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
- `ws.accept_tls_pkcs12(listen_fd, timeout_ms, pkcs12_bytes, passphrase, tls_opts)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
  - Rolling helper for loopback fixtures and basic WSS servers; wraps `tcp.accept` + `tls.wrap_server_pkcs12` + the WS handshake.
- `ws.close(conn)` → `0` (closes underlying TCP/TLS connection)
- `ws.send_text_client(conn, text, timeout_ms)` → `0` on success, or `-errno`
  - Client frames are **masked** (required by RFC6455).
- `ws.send_text_server(conn, text, timeout_ms)` → `0` on success, or `-errno`
  - Server frames are **unmasked**.
- `ws.send_ping_client(conn, payload, timeout_ms)` → `0` on success, or `-errno`
- `ws.send_ping_server(conn, payload, timeout_ms)` → `0` on success, or `-errno`
- `ws.recv_text(conn, timeout_ms)` → `{"ok":1,"v":string}` or `{"ok":0,"err":string}`
  - v0.1 behavior: internally handles **ping/pong/close** frames (auto-pong + ignore pongs).

## Scope / limitations (v0)

This is intentionally minimal so we can gate correctness across Tier‑1 first.

- URL: `ws://<host>[:port][/path]`
  - IPv4 literal hosts work without DNS
  - hostname hosts resolve via DNS A:
    - pass an explicit resolver config (`ws.connect_resolver`)
    - or rely on `dns.default_resolver` (env `OREN_DNS_SERVER`, else system DNS on Windows, else `/etc/resolv.conf` on POSIX)
- URL: `wss://<host>[:port][/path]`
  - TLS provider availability is OS-dependent; see `docs/NET_TLS.md`
  - loopback fixtures rely on `opts["tls"]["insecure_skip_verify"]=1` + `opts["tls"]["pin_cert_sha256_hex"]="..."` for deterministic offline behavior (pin enforced by `std:net/tls`)
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
- Fixed (2026-01-08): sporadic WS `ETIMEDOUT` flakes under `spawn` were also caused by **TIME scratch buffer races**:
  - `oren_time_unix_ns()` and `oren_time_mono_raw()` used shared global scratch buffers without synchronization.
  - Under concurrent use, that could corrupt timeout math (e.g. compute `rem_ms=0` spuriously), making frame reads “timeout” even when the peer had sent data.
  - The native runtime now keeps TIME scratch buffers **per-thread** (stored in the thread node), with a locked global fallback for early/unknown-thread paths.

### Regression sensitivity (x64-windows)

Even small “semantics‑no‑op” changes can re-surface latent x64‑windows backend/runtime issues and show up first as WebSocket timeouts (while TCP/UDP/HTTP still pass). One concrete root cause was the TIME scratch buffer race fixed on 2026-01-08 (see note above), but WS remains a high-signal end-to-end fixture.

Practical guidance:

- Treat `./scripts/verify_native_net_matrix.sh --targets x64-win` as a **hard gate** for any runtime/backend work, even if the change “shouldn’t affect NET”.
- If you suspect a rare flake, reproduce it **without huge logs** by running:
  - `OREN_WS_ECHO_N=50 ./scripts/verify_native_net_matrix.sh --targets x64-win` (or run `tests/native/test_ws_echo_loopback.oren` directly on Win11/WSL2).
