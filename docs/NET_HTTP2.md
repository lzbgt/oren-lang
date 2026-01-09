# HTTP/2 in Oren (Rolling Status)

This document captures the current (rolling) state of Oren’s HTTP/2 support in the stdlib, and the concrete regression fixtures that keep it stable across Tier‑1 targets.

Tier‑1 targets (current policy):

- `arm64-macos` (local)
- `arm64-linux` (persistent docker container)
- `x64-linux` (remote WSL2)
- `x64-windows` (remote Win11)

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

Historically, the native backend used an untagged “i64 carrier” value model, which caused a real hazard:

- **`0 == nil` could evaluate true** (and similarly `0 == false`), because `nil/false/0` shared the same raw representation in some compare paths.

This is especially dangerous in protocol code because integer `0` values are valid and meaningful
(example: HTTP/2 SETTINGS like `ENABLE_PUSH=0`).

Mitigation status (2026-01-09, rolling):

- The compiler optimizer now folds **type-mismatched `==`/`!=`** on literals (e.g. `0 == nil` → `false`).
- It also folds `id == nil` / `id != nil` when `id` is a local that is trivially proven non-nil (e.g. `var x = 0; if x == nil { ... }` → `false`).
- Regression gate: `make test` (quick integration includes explicit `0/nil/false` parity asserts).

Remaining work:

- Full semantic parity still requires the tagged value model described in `docs/NATIVE_TAGGED_VALUE_REPRESENTATION.md`,
  so comparisons involving values of unknown dynamic type remain a native-backend “rolling” area.
  Track in `docs/TODOS.md` / `docs/LANGUAGE_STATUS_AND_GAPS.md`.

## How To Verify

Fast local checks:

- `make verify-native-quick`
- `./scripts/verify_native_net_matrix.sh --targets local --local-only`

Full Tier‑1 NET matrix:

- `./scripts/verify_native_net_matrix.sh --targets arm64-linux,x64-win,x64-wsl`

Notes:

- The NET matrix script has a rolling hang guard: `OREN_NATIVE_BUILD_TIMEOUT_SECS` (default `10`) per `oren build ...` step.
- Avoid adding fixtures that generate huge logs; prefer concise loopbacks with deterministic asserts.
