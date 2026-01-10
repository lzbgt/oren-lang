# HTTP/2 in Oren (Rolling Status)

This document captures the current (rolling) state of Oren’s HTTP/2 support in the stdlib, and the concrete regression fixtures that keep it stable across Tier‑1 targets.

Tier‑1 targets (current policy):

- `arm64-macos` (local)
- `arm64-linux` (persistent docker container)
- `x64-linux` (remote WSL2)
- `x64-windows` (remote Win11)

Last verification (fact):

- 2026-01-11: `make verify-native-net-skip-remote` passed on:
  - `arm64-macos` (local)
  - `arm64-linux` (docker container `c7e5f7bd9f5c`)
- 2026-01-11: `make verify-x64-linux-qemu-tls` passed on:
  - `x64-linux` under QEMU in docker container `c7e5f7bd9f5c` (stage1 + stage2; includes HTTP/2 + HPACK loopback/smokes)
- `x64-linux` / `x64-windows` runs require the remote Win11+WSL2 host; see `docs/REMOTE_X64_ENV.md` if the proxy/hostname is unavailable.

## Modules

Oren splits HTTP/2 into small layers:

- `std:net/http2` (`lib/std/net/http2.oren`)
  - Framing primitives (client preface bytes, frame header encode/decode).
  - Small payload codecs (currently: SETTINGS payload codec).
  - This module is intentionally “dumb framing”; it is not a full HTTP/2 stack.
- `std:net/hpack` (`lib/std/net/hpack.oren`)
  - HPACK encode/decode v0: static+dynamic tables, Huffman encode/decode, header block encode/decode.
- `std:net/http2_client` (`lib/std/net/http2_client.oren`)
  - Minimal client facade built on top of `std:net/tls` + `std:net/http2` + `std:net/hpack`.
  - Purpose: let Tier‑1 loopback fixtures exercise *stdlib behavior* (not copy/pasted framing logic in tests).

## What Works Today (Evidence-Backed)

### HTTP/2 framing smoke (SETTINGS/ACK + PING/ACK)

- Fixture: `tests/native/test_http2_preface_loopback.oren`
- Coverage:
  - Client preface
  - SETTINGS / SETTINGS+ACK
  - PING / PING+ACK
- Gate: `scripts/verify_native_net_matrix.sh` (stage1 + stage2; all Tier‑1)

### HPACK smoke + encoder regression

- Smokes:
  - `tests/native/test_hpack_smoke.oren` (RFC 7541 Appendix C.2 + C.4.1 decode path)
  - `tests/native/test_hpack_encode_rfc_c41.oren` (RFC 7541 Appendix C.4.1 exact bytes)
- Gate: `make test` includes a fast native integration, but for full NET coverage use `scripts/verify_native_net_matrix.sh`.

### HTTP/2 request/response loopback (single stream, over TLS)

- Fixture: `tests/native/test_http2_headers_loopback.oren`
- Architecture:
  - The **server** side uses `std:net/http2` primitives and verifies the decoded request headers.
  - The **client** side uses `std:net/http2_client` (handshake + request).
- Coverage:
  - TLS ALPN `h2` (best-effort assert on macOS; strict on Linux/Windows where providers expose ALPN)
  - SETTINGS payload decode (expects `ENABLE_PUSH=0`)
  - SETTINGS/ACK handshake
  - HEADERS + CONTINUATION reassembly (forced via deliberate splitting)
  - DATA + END_STREAM response body (`"ok"`)
- Gate: `scripts/verify_native_net_matrix.sh` (stage1 + stage2; all Tier‑1)

## API Notes (Rolling)

### `std:net/http2_client`

Current surface (v0):

- `http2_client.new(conn, timeout_ms, opts)`
  - Writes client preface + client SETTINGS.
  - Expects server SETTINGS + server ACK, then sends ACK for server settings.
  - Returns `{"ok":1,"c":client}` on success.
- `http2_client.request(c, headers, body_bytes, opts)`
  - Sends one request on the next odd stream id:
    - HEADERS (+ optional CONTINUATION)
    - optional DATA (END_STREAM)
  - Reads one response:
    - HEADERS (+ CONTINUATION) then DATA until END_STREAM
  - Returns `{"ok":1,"status":<int>,"headers":<list>,"body":<u8_buf>}` on success.

Options (v0):

- `opts["settings"]`: list of `[id, value]` pairs for the initial SETTINGS frame.
- `opts["split_headers_at"]`: split HEADERS payload at this byte count to force a CONTINUATION frame (fixture coverage).

Non-goals (v0):

- Multiplexing multiple streams
- Full RFC stream state machine
- Flow control / WINDOW_UPDATE
- Server push

## Native Backend Semantics Note (Rolling)

Oren’s language semantics require **type-strict equality** (`nil` distinct from `false`, `int` distinct from `nil`, etc).

Current rolling status (2026-01-11):

- Native mode uses **runtime singleton values** for `nil`, `false`, and `true` (they are distinct non-zero values stored in runtime globals).
  - This ensures `0` (int zero) stays distinct from `nil`/`false` in the common case, which matters for protocols where `0` is meaningful (e.g. SETTINGS values like `ENABLE_PUSH=0`).
- The compiler also includes a correctness guardrail: it rejects `bool/int/float == nil` comparisons when the scalar side is statically known.

Remaining work:

- Full semantic parity still requires the tagged value model described in `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md` (notably: robust `int` vs `float` tagging in native mode).

## How To Verify

Fast local checks:

- `make verify-native-quick`
- `./scripts/verify_native_net_matrix.sh --targets local --local-only`

Full Tier‑1 NET matrix:

- `./scripts/verify_native_net_matrix.sh --targets arm64-linux,x64-win,x64-wsl`

Notes:

- The NET matrix script has a rolling hang guard: `OREN_NATIVE_BUILD_TIMEOUT_SECS` (default `10`) per `oren build ...` step.
- Avoid adding fixtures that generate huge logs; prefer concise loopbacks with deterministic asserts.
