# TLS / HTTPS / WSS (stdlib, native backend) — rolling

This doc defines the **stdlib contract** for TLS in Oren and the implementation strategy needed to support:

- `https://` in `std:net/http`
- `wss://` in `std:net/ws`
- “secure TCP” primitives in `std:net/tcp` (via a TLS wrapper)

Related crypto modules (shared, not NET-specific):

- `std:crypto/pem` (decode PEM blocks)
- `std:crypto/x509` (small certificate helpers; rolling v0)

Tier‑1 targets (rolling intent):

- `arm64-macos`
- `arm64-linux` (docker container)
- `x64-windows` (remote Win11)
- `x64-linux` (remote WSL2)

## 1) Constraints (why this design exists)

### 1.1 No external connectivity in regression

Tier‑1 NET gates are loopback-only (`scripts/verify_native_net_matrix.sh`). TLS must be testable offline:

- the test suite should not contact public hosts
- results must be deterministic (bounded timeouts, no flaky DNS/CA store dependencies)

### 1.2 Stdlib must be self-contained (no Makefile flags)

For portability, stdlib must not require consumers to pass `--link ...` manually.

Rolling rule:

- OS bindings that require dynamic libraries should declare them on the `ffi` statement itself via:
  - `@ffi.link("...")` (portable; maps to `--link ...`)
  - `@ffi.dll("...")` (Windows x64 convenience; treated as `--link` in the build pipeline too)

See:

- `docs/TODOS.md` (native FFI parity)
- `docs/NATIVE_BACKEND.md` (native dynamic linking model)

## 2) Stdlib API (`std:net/tls`)

Goal: a **small, syscall-first shaped** API that can wrap a TCP socket and provide a stable surface for HTTPS/WSS.

### 2.1 Types / shapes (v0)

We model a TLS connection as an **opaque map**:

- `{"fd": int, "impl": string, "state": ...}`

The `state` field is backend-specific (pointer/handle integers), and is not accessed by user code.

### 2.2 Client connect / wrap

Functions (rolling v0):

- `tls.connect(host_or_ip, port, timeout_ms, opts)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
  - Dial TCP + do TLS handshake.
  - DNS behavior:
    - if `host_or_ip` looks like an IPv4 literal, no DNS is performed
    - otherwise, the host is resolved via DNS A query
      - if `opts["resolver"]` is provided, it is used
      - else `dns.default_resolver(timeout_ms)` is used internally
- `tls.wrap_client(fd, server_name, timeout_ms, opts)` → `{"ok":1,"conn":map}` or `{"ok":0,"err":string}`
  - Wrap an already-connected TCP `fd` (useful for proxies).

`opts` (rolling v0):

- `opts["alpn"]`: list of strings (e.g. `["h2", "http/1.1"]`) (optional)
- `opts["verify"]`: `1|0` (default: `1`) (planned; provider-dependent)
- `opts["insecure_skip_verify"]`: `1|0` (default: `0`) (implemented on macOS + Linux + Windows providers; see §5)
  - Intended for **offline loopback fixtures** only; callers should pin the peer cert (see §3).
- `opts["server_name"]`: override SNI/server name when dialing by IP (used by loopback fixtures and proxies)
  - Note: `tls.connect` does not send IPv4 literals as SNI by default; use `opts["server_name"]` when needed.
- `opts["resolver"]`: optional DNS resolver config (`dns.resolver(...)`) used by `tls.connect` for hostname lookups.
- `opts["pin_cert_sha256_hex"]`: optional pinned leaf certificate hash (SHA-256 of DER; hex string)
  - Enforced by `tls.wrap_client` post-handshake (so higher layers don’t duplicate pinning logic).

### 2.3 IO

- `tls.read_into(conn, buf, cap, timeout_ms)` → `n` or `-errno`
- `tls.write_from(conn, ptr, len, timeout_ms)` → `n` or `-errno`
- `tls.close(conn)` → `0` or `-errno`

Note:

- The IO functions must be timeout-bounded and should follow the existing NET policy:
  - treat readiness waits as advisory
  - retry until deadline expires

## 3) Testing strategy (offline + deterministic)

TLS needs a loopback server fixture that is consistent across OS.

Planned approach:

1) Embed a deterministic self-signed certificate + private key in the test fixture (PEM or raw DER bytes).
2) Use a fixed hostname (e.g. `oren.test`) and rely on:
   - explicit loopback DNS resolver injection (already done for HTTP/WS tests), or
   - direct `127.0.0.1` connect and SNI override via `server_name`.
3) Verify by **pinning**:
   - `opts["pin_sha256"]` = SHA-256 of SPKI or full cert DER

This avoids relying on host CA stores (which vary by OS and are not deterministic in tests).

Implementation note (macOS provider bring-up):

- Oren’s syscall-first native runtime currently implements language-level `spawn` as **fork-based** (process boundary).
- Apple Security/CoreFoundation APIs are not guaranteed to be safe when called in a post-fork child without `exec`.
- The Tier‑1 TLS loopback fixture therefore uses a **fork+exec** server mode (single binary with `server` argv) instead of `spawn`.

## 4) Implementation plan (providers)

TLS is implemented via **OS providers** (FFI) per Tier‑1 OS:

- `arm64-macos`: Security.framework (SecureTransport / TLS APIs)
- `x64-windows`: SChannel / SSPI (`secur32.dll`, `crypt32.dll`)
- `arm64-linux` + `x64-linux`: OpenSSL 3 (loaded lazily at runtime via `dlopen(..., RTLD_GLOBAL)`)

Rationale:

- Native backend already supports dynamic linking (`--link`) on all Tier‑1 targets.
- Provider APIs handle modern TLS versions/ciphersuites, and can be validated incrementally.

## 5) Current status

- `std:net/tls` exists (rolling v0):
  - macOS provider (SecureTransport) is implemented for:
    - `tls.wrap_client`
    - `tls.wrap_server_pkcs12`
    - `tls.read_into` / `tls.write_from` / `tls.close`
    - `tls.peer_cert_sha256_hex` (leaf certificate SHA-256 of DER)
  - Client verification behavior:
    - default: platform verification (may reject loopback self-signed fixtures)
    - `opts["insecure_skip_verify"]=1`: disables platform verification so deterministic fixtures can rely on pinning
  - macOS provider requires a small toolchain bridge:
    - SecureTransport IO callbacks must be passed as **raw function pointers**
    - Oren marks these callbacks with `@ffi.export` and resolves them via `dlsym(RTLD_DEFAULT, ...)`
    - SecureTransport has two distinct IO APIs:
      - IO callbacks (`SSLSetIOFuncs`) use 3-arg `SSLReadFunc`/`SSLWriteFunc` signatures
      - application IO (`SSLRead`/`SSLWrite`) use 4 args (`data`, `dataLength`, `processed*`)
    - SecureTransport APIs return `OSStatus` (signed 32-bit). `ffi` declarations that return `OSStatus`
      are annotated with `@ffi.ret("i32")` so the native backend sign-extends return values correctly.
- Regression gate:
  - `tests/native/test_tls_loopback.oren` is integrated into `scripts/verify_native_net_matrix.sh` (stage1 + stage2; local loopback).
- Higher-level integrations (rolling):
  - `std:net/http` supports `https://` via `http.get_response_resolver_opts` / `http.get_response_opts` (uses `tls.wrap_client`).
    - Regression gate: `tests/native/test_https_get_loopback.oren` (loopback-only; deterministic; uses pinning).
  - `std:net/ws` supports `wss://` via `ws.connect_resolver_opts` (uses `tls.wrap_client`).
    - Server helper: `ws.accept_tls_pkcs12` (wraps `tcp.accept` + `tls.wrap_server_pkcs12` + WS handshake).
    - Regression gate: `tests/native/test_wss_echo_loopback.oren`.
- Note: TLS provider availability is still OS-dependent; on non-macOS/non-Linux/non-Windows targets these fixtures compile but exit(0) until providers land.

### 5.1 Linux provider (OpenSSL)

As of **2026-01-08 (rolling)**, `std:net/tls` has a Linux provider implemented in `lib/std/net/tls_linux_openssl.oren` (facade: `lib/std/net/tls.oren`):

- Dynamic linking:
  - OpenSSL libraries are **not** added to DT_NEEDED by default.
  - `std:net/tls` loads `libcrypto.so.3` + `libssl.so.3` lazily via `dlopen(..., RTLD_GLOBAL)` during `_openssl_init()`.
    - This avoids forcing non-TLS binaries that merely import `std:net/http` / `std:net/ws` to have OpenSSL present at program load time.
    - If OpenSSL is not present, TLS functions return a structured error instead of the whole binary failing to load.
- Implemented surface:
  - `wrap_client`, `wrap_server_pkcs12`
  - `read_into`, `write_from`, `close`
  - `peer_cert_sha256_hex` (leaf certificate SHA-256 of DER; via `SSL_get1_peer_certificate` + `i2d_X509`)
- Regression gate:
  - `scripts/verify_native_net_matrix.sh --targets arm64-linux,x64-wsl` runs:
    - `tests/native/test_tls_loopback.oren`
    - `tests/native/test_https_get_loopback.oren`
    - `tests/native/test_wss_echo_loopback.oren`

Implementation notes (Linux):

- **SIGPIPE is ignored** (`signal(SIGPIPE, SIG_IGN)`) so failed socket writes return `-EPIPE` instead of killing the process.
- **FFI `int` return lowering is explicit** (compiler-level):
  - Many OpenSSL APIs return `int` (signed 32-bit). Native ABIs do not require the upper 32 bits of the return register to be sign-extended.
  - Oren uses 64-bit value carriers, so the `ffi` declaration must specify the ABI return width, e.g. `@ffi.ret("i32")`, and the native backend sign-extends the return after the call.
- **SNI is wired** on Linux (client):
  - `SSL_set_tlsext_host_name` is a macro in OpenSSL (not a linkable symbol), so we wire SNI via `SSL_ctrl(...)`.
  - Oren uses numeric constants taken from the Tier‑1 Linux headers (`libssl-dev`, Ubuntu noble):
    - `SSL_CTRL_SET_TLSEXT_HOSTNAME = 55` (`/usr/include/openssl/ssl.h`)
    - `TLSEXT_NAMETYPE_host_name = 0` (`/usr/include/openssl/tls1.h`)
  - `std:net/tls` chooses the server-name as:
    - prefer explicit `wrap_client(..., server_name, ...)`
    - fallback to `opts["server_name"]` if the argument is missing (useful for already-connected sockets / proxies)
- **ALPN is wired** on Linux (client offer):
  - `opts["alpn"]` is interpreted as a list of protocol strings (e.g. `["h2","http/1.1"]`).
  - The OpenSSL provider builds the wire-format protocol list and calls `SSL_set_alpn_protos`.
  - Note: `SSL_set_alpn_protos` returns **0 on success** (reversed convention); see sources below.

Sources captured for audit/reference:

- `project-doc/web/openssl/SSL_connect.html`
- `project-doc/web/openssl/SSL_read.html`
- `project-doc/web/openssl/SSL_get_error.html`
- `project-doc/web/openssl/PKCS12_parse.html`
- `project-doc/web/openssl/d2i_X509.html`
- `project-doc/web/openssl/SSL_CTX_ctrl.html` (covers `SSL_ctrl` return semantics)
- `project-doc/web/openssl/SSL_CTX_set_alpn_select_cb.html` (covers `SSL_set_alpn_protos` return semantics)

### 5.2 Windows provider (Schannel / SSPI)

As of **2026-01-08 (rolling)**, `std:net/tls` has a Windows provider implemented in `lib/std/net/tls_windows_schannel.oren` (facade: `lib/std/net/tls.oren`):

- Dynamic linking:
  - `@ffi.dll("secur32.dll")` (SSPI)
  - `@ffi.dll("crypt32.dll")` (PFX import + cert hash)
- Implemented surface:
  - `wrap_client`, `wrap_server_pkcs12`
  - `read_into`, `write_from`, `close`
  - `peer_cert_sha256_hex` (leaf hash via `SECPKG_ATTR_REMOTE_CERT_CONTEXT` + `CERT_SHA256_HASH_PROP_ID`)
- Regression gate:
  - `scripts/verify_native_net_matrix.sh --targets x64-win` runs (stage1 + stage2):
    - `tests/native/test_tls_loopback.oren`
    - `tests/native/test_https_get_loopback.oren`
    - `tests/native/test_wss_echo_loopback.oren`

Implementation notes (Windows):

- **Server handshake must start with input**:
  - `AcceptSecurityContext` is not guaranteed to establish a context handle when called with a zero-length input token.
  - The server handshake loop therefore reads the initial ClientHello bytes before the first `AcceptSecurityContext` call.
- **Schannel `DecryptMessage` buffer semantics**:
  - The plaintext DATA buffer can be a pointer into the encrypted buffer.
  - Copy plaintext out before shifting the EXTRA encrypted tail, and use overlap-safe moves when shifting tails.
