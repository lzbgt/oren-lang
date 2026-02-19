# OBC Portability and Distribution (Rolling)

This document consolidates the OBC portability/linking contract and distribution security model.

## OBC (Oren Bytecode) — Portability + Module Linking (Rolling)

Oren `.obc` bytecode is designed as an **AVM universal artifact**:

- `.obc` should have **no platform meaning** (no “macOS vs Linux”, no “arm64 vs x64” semantics).
- AVM itself is a native program that depends on the host OS/arch for syscalls and memory mapping.
- The **contract** is: the same `.obc` executes with the same observable results across AVM builds.

This document consolidates the rolling rules for portability gates and for module linking (OBX metadata).

## 1) Portability contract and gate (implemented)

### What is compared

`./avm` supports printing deterministic hashes:

- `RESULT_HASH` — hash of program-visible outputs (logical results)
- `TRACE_HASH` — hash of trace/events (execution trace surface)

Portability means **both hashes match** across platforms.

### Current portability gate

Use the script:

- `tools/verify_obc_portability.sh`

Or via Make:

- `make obc-portability`

It verifies the same `.obc` (`tests/avm/test_smoke_suite.oren`) runs identically on:

- macOS arm64 (host)
- linux/arm64 (persistent docker container)
- linux/x86_64 (WSL2 when available on remote Win11 host)

Outputs are stored under:

- `build/tmp/obc_portability/`

### Requirements

1) Local host

- `./oren` and `./avm` built (normal `make test` already builds them).

2) Linux docker container (arm64)

This repo uses an **already-running** persistent Ubuntu toolchain container (it must exist and be
running; the scripts do **not** create a container for you).

- container id/name default: `c7e5f7bd9f5c` (override via `OREN_LINUX_DOCKER_ID=...`)

The portability gate syncs **tracked** sources into `/work/repo`, rebuilds AVM inside the
container, then executes the host-built `.obc`.

3) Remote x64 host (Win11, WSL2 optional)

The script uses the existing ssh proxy workflow (see `docs/PLATFORMS.md`) and runs AVM inside
WSL2 (Linux x86_64) when available. If WSL2 is unavailable, skip the remote Linux leg and keep the
Windows leg for native gates.

Environment variables (defaults match the repo’s existing conventions):

- `OREN_REMOTE_X64_HOST` (default: `lzbgt@pc.work`)
- `OREN_REMOTE_X64_PROXY` (default: `ProxyCommand=socat - PROXY:hubstack.cn:%h:%p,proxyport=6002`)
- `OREN_REMOTE_X64_UNIX_ROOT` (default: `/Users/lzbgt/tmp_oren`)

## 2) Module linking: OBX metadata inside `.obc`

This repo currently treats `.obc` as a **single self-contained program** (AVM bytecode).
For production-grade distribution (especially “compiler-in-AVM”), we also need a way to ship
**precompiled bytecode libraries** (e.g. stdlib) and link them into a final program `.obc`.

The rolling v0 approach is:

- `.obc` execution semantics stay unchanged (AVM ignores module metadata).
- The compiler optionally appends an **unused** `BYTES` constant containing an “OBX payload”.
- Tooling/linker reads OBX metadata to rebase code + resolve symbols.

### Goals

- Allow Oren/AVM to compile user source **without shipping stdlib sources**.
- Keep `.obc` execution semantics unchanged (AVM ignores module metadata).
- Keep the format simple enough to implement in Oren itself (compiler-in-AVM).

### Non-goals (v0)

- Runtime dynamic module loading (`import` at runtime).
- Stable ABI guarantees across releases (rolling mode).
- Exporting “globals as data symbols” (v0 focuses on function symbols).

### OBX payload format (binary)

The OBX payload is a byte blob stored inside a `BYTES` constant:

- prefix: ASCII `OREN_OBX\n1\n`
- `u16` `module_name_len`, followed by `module_name` UTF-8 bytes
- `u16` `export_count`
  - repeated `export_count` times:
    - `u16` `name_len`, followed by symbol name UTF-8 bytes
    - `u32` `addr` (**0-based** byte offset into this module’s code section)
- `u16` `reloc_count`
  - repeated `reloc_count` times:
    - `u16` `name_len`, followed by symbol name UTF-8 bytes
    - `u32` `pos` (**0-based** byte offset into this module’s code where a `u32` address must be patched)
    - `u8`  `kind`:
      - `0` = `CALL32` target relocation
      - `1` = `PUSH_FUNC32` target relocation

The linker rebases `addr` and `pos` as it concatenates modules.

### Stable symbol names for `std:` imports

To make separate compilation feasible, stdlib modules use a stable, deterministic prefix:

- `std:math` uses prefix `STD_math_`
- `std:net/http` uses prefix `STD_net_http_`

Then `fn sqrt(x)` inside `std:math` becomes an exported symbol:

- `STD_math_sqrt`

This stable naming is required so user code compiled in “extern stdlib” mode calls the same
symbol names that exist in the precompiled stdlib bundle.

### Compiler flags (rolling)

Build a library/bundle with exports:

```
./oren build lib/std/stdlib_avm.oren --backend bytecode -o build/stdlib_bundle.obc --obc-lib
```

This emits a normal runnable `.obc` plus an OBX payload containing exported function symbols.

Rolling helper scripts:

- Build stdlib bundle and (optionally) a compiler `.obc`: `scripts/build_avm_plugins.sh`
  - Override bundle root via env `OREN_STDLIB_BUNDLE_ROOT=...`
- Build+run a host `avm` smoke (proves OBX linking works end-to-end):
  `scripts/verify_avm_bytecode_link_smoke.sh`

Build an app linking against a precompiled stdlib:

```
./oren build app.oren --backend bytecode -o app.obc --stdlib-mode obc --stdlib-obc build/stdlib_bundle.obc
```

This mode:

- keeps unresolved calls as relocations (instead of hard compile errors)
- links the stdlib bundle `.obc` into the final output `.obc`
- patches relocations using OBX exports

### Implementation notes

- The linker patches:
  - `PUSH_CONST` indices (const pool concatenation)
  - `LOAD_GLOBAL` / `STORE_GLOBAL` indices (global index rebasing)
  - `CALL32` / `PUSH_FUNC32` absolute code addresses (code section rebasing)
  - OBX relocations (symbol resolution)
- Relative jump offsets (`JMP32`/`JMP_IF32`) remain valid under concatenation.
- To keep execution correct when concatenating multiple modules, the linker strips a trailing
  `HALT` opcode from each **non-final** module during concatenation. This prevents linked libraries
  from terminating the pc=0 “skip function bodies” chain before reaching the main program’s entry.

### Files

- Linker implementation: `lib/compiler/obc_link.oren`
- Stdlib bundle root (AVM-safe subset): `lib/std/stdlib_avm.oren`
- Stdlib bundle root (full, rolling, may include native-only helpers): `lib/std/stdlib.oren`
- Module prefixing + extern stdlib mode: `lib/compiler/compiler/020_modules_linking.oren`

## 3) Known gaps / next steps

1) **Native Windows AVM**
   - Today, AVM is a POSIX-style program (`unistd.h`, `sys/mman.h`, etc.).
   - Running `.obc` directly on Windows (without WSL2) requires a Windows AVM port (Win32 / NT syscalls).

2) **Compiler bytecode invariants**
   - The compiler currently forces a single bytecode ABI profile (`target=avm`, `arch=avm64`) to prevent
     host-specific lowering from leaking into `.obc`.
   - This should converge to “bytecode compilation ignores host target entirely” as the IR and lowering
     become fully portable.

## AVM App-Store Model: Root CA, Signed OBC, and Multiverse Updates (Rolling)

This document defines a **production-direction** security model for:

- distributing `.obc` “binary components” (stdlib bundle, compiler bundle, tools)
- allowing a parent AVM universe to **fetch updates** and “patch” child universes safely
- ensuring any node can verify the provenance of an artifact **offline** (no network trust)

This is intentionally “app store–like”: there is a *root trust anchor*, signed artifacts, and policy gating.

## Threat Model (What we defend against)

We assume:

- the network is hostile (MITM, replay, tampering)
- storage is hostile (cache poisoning, corrupted artifacts)
- child universes are untrusted and must not escalate privileges

We want:

- a parent node can retrieve/update components safely
- nested universes verify child `.obc` before execution (already required by the verifier)
- reproducibility + auditability via hashes (already part of AVM job model)

## Root of Trust

We maintain an offline **root signing key** (Root CA).

- The **root private key must never be committed** into this repo.
- The **root public key** is safe to embed into AVM builds (it is not secret).

Operational requirement:

- Root secrets live in a sibling directory **outside the repo**: `../oren-ca/`

Build-time embedding (rolling):

- AVM can embed a set of trusted root **public keys** in release builds (for “no flags needed” verification).
- The build reads root pubkeys from either:
  - `AVM_EMBED_ROOT_PUBKEY_HEX` (comma-separated 64-hex strings), or
  - `../oren-ca/avm_root_pubkeys.hex` (one 64-hex pubkey per line)
- Implementation detail: `make avm` generates `build/avm_root_pubkey.inc` via `tools/gen_avm_root_pubkeys_inc.sh`.

## Artifact Signature Model (Rolling v0)

We define a signature payload stored inside `.obc` as an unused `BYTES` constant:

- prefix: `OREN_SIG\n1\n`
- payload: algorithm id + key id + signature bytes

The signature covers a canonical hash of the `.obc` **excluding** signature/metadata constants:

- `OREN_SIG\n1\n` (signature payload)
- `OREN_CERTS\n1\n` (delegation chain payload)

Rationale:

- `.obc` can embed metadata constants (OREN_META, OREN_OBX). We must avoid circular signing.
- The AVM must be able to verify with only `.obc` bytes (self-contained distribution).

## Delegated Signing (Org / Developer Certificates)

Root-signing every artifact does not scale operationally. Rolling mode supports a minimal
delegation chain:

- root → organization (may issue)
- organization → developer (leaf signing key)

The `.obc` embeds the cert chain inside an unused BYTES constant:

- `OREN_CERTS\n1\n` (leaf-first chain)

Important detail: `OREN_CERTS` is treated as **verification metadata** and is excluded from the
canonical signature hash (along with `OREN_SIG`). This allows:

- updating/repacking cert chains without re-signing the `.obc` payload bytes
- keeping the leaf signature stable while rotating intermediate cert packaging

The AVM verifies:

1) chain signatures back to the trusted root pubkey
2) issuer `can_issue` enforcement for intermediate certs
3) `.obc` signature key id matches the leaf cert key id
4) `.obc` signature verifies under the leaf pubkey

Rolling extension (cert constraints):

- Certs may carry an issuer-defined capability ceiling (`allow_domains_mask` in `OREN_CERT\n2\n`).
- AVM enforces that the artifact’s bytecode only uses native domains within the delegated mask,
  independent of host/user allowlists.

Spec: `docs/OBC_DISTRIBUTION.md`.

## Verification Policy in AVM

Two independent “verify” layers exist:

1) **Bytecode verifier** (structural safety): prevents malformed programs from crashing/hanging the VM.
2) **Signature verifier** (provenance): prevents executing untrusted binaries.

Rolling policy:

- For **nested universes** (`avm.run_obc_bytes`), signature verification should be enabled by default once stable.
- For **host CLI** (`./avm file.obc`), signature verification is opt-in via flags/env until the ecosystem migrates.

## Update / Patch Model for Multiverse

We treat “patching a child universe” as:

- parent obtains a new signed `.obc` (full artifact or delta patch)
- parent verifies signature locally
- parent passes verified `.obc` bytes to child execution (`avm.run_obc_bytes`)
- child (or host service) re-verifies signature before running

Important: the parent must never be able to bypass child verification by “already verified on host”.
Verification must happen at the enforcement boundary.

## App Store Service (Future)

The “store” is just a distribution service for:

- signed artifacts (`.obc`)
- manifests (JSON): names, versions, hashes, dependencies, policy requirements

The security property is not “TLS” but “signatures”:

- even if transport is compromised, signatures prevent tampering.

Planned directions:

- a simple HTTP(S) endpoint for manifests + artifacts
- optional websocket for streaming updates
- compatibility with VirtualNET fixtures for deterministic simulation runs

## Running crypto inside AVM vs host crypto

Two viable designs exist in rolling mode:

1) **Host-side crypto (current implementation)**
   - AVM binary (C) verifies `OREN_SIG` using a vendored ed25519 verifier.
   - Pros: fast, small amount of bytecode changes.
   - Cons: trust is anchored in the AVM binary (still acceptable for many deployments).

2) **Bytecode crypto (planned)**
   - Implement SHA-256 / ed25519 verification in pure Oren (no FFI), compile to `.obc`, and link it.
   - Pros: the same verification logic can run inside nested universes (no libc/FFI dependency).
   - Cons: slower and more work; must be carefully tested for correctness/determinism.

Rolling recommendation:

- Keep host crypto as the enforcement boundary for `avm.run_obc_bytes`.
- Build bytecode crypto in parallel for portability/testing and to support more advanced “store logic as `.obc`” workflows.

Bootstrapping note:

- You can ship crypto code as `.obc` (pure Oren, no libc/FFI) and load it in AVM *after* the loader verifies its signature.
- You cannot eliminate a small trusted verifier in the AVM binary if you want signature enforcement at the boundary; otherwise you have a “who verifies the verifier?” loop.

## Key Handling

- Root private key: stored in `../oren-ca/` only (never in-repo).
- Root public key: embedded in AVM builds or passed explicitly for verification.
- Key rotation: supported by “key id” in the signature payload; AVM can accept a set of trusted pubkeys.

## Related Docs

## Delegated Signing Certificates (OREN_CERTS) — Rolling

This document specifies a **minimal certificate chain** format used to delegate signing
authority from a Root CA to organizations and developers.

The goal is “app store” style provenance verification for `.obc` artifacts.

## Why not X.509?

X.509 is heavy:

- ASN.1 parsing complexity
- large attack surface
- lots of semantics we don’t need in rolling mode

We only need:

- key delegation (root → org → dev)
- an explicit “can issue” bit for intermediate certs
- a stable identifier for issuers (key id)
- signatures over deterministic bytes

## High-level model

- A **root public key** is the trust anchor (embedded in AVM or provided externally).
- An **organization cert** is signed by the root and has `can_issue=1`.
- A **developer cert** is signed by the org and has `can_issue=0` (default).
- Artifacts (`.obc`) are signed by the leaf key (developer or org).
- The `.obc` embeds the cert chain so AVM can verify provenance offline.

## Where certs live in `.obc`

`.obc` embeds an **unused BYTES constant** with payload prefix:

- `OREN_CERTS\n1\n`

This constant is not referenced by bytecode execution; it is verification metadata only.

Note: `OREN_CERTS` is **excluded** from the `.obc` signature hash (along with `OREN_SIG`) so
the chain can be updated without requiring re-signing the artifact, as long as the leaf
key remains the signer and the chain verifies to the trusted root.

## Payload format: OREN_CERTS v1

Bytes layout:

- ASCII prefix: `OREN_CERTS\n1\n`
- `u16` count (little-endian)
- repeated `count` times:
  - `u16` cert_len
  - `cert_len` bytes: a single `OREN_CERT\n1\n` blob

The order is **leaf-first**:

- cert[0] is the leaf (developer) cert
- cert[1] is the issuer (org) cert
- ...
- the last cert is signed by the trusted root pubkey

## Certificate format: OREN_CERT v1

Each cert blob is fixed-format:

- ASCII prefix: `OREN_CERT\n1\n`
- `u8` algo (`1` = ed25519)
- `u8` flags:
  - bit0 `can_issue` (1 = may issue derived certs)
- `u64` not_before (LE) (rolling; `0` means “unset”)
- `u64` not_after  (LE) (rolling; `0` means “unset”)
- `subject_pubkey[32]`
- `issuer_keyid8[8]` = `sha256(issuer_pubkey)[:8]`
- `sig[64]` ed25519 signature over `SHA256(cert_body_no_sig)`

Where `cert_body_no_sig` is the cert bytes up to (but excluding) `sig[64]`.

## Certificate format: OREN_CERT v2 (constraints)

v2 extends v1 with a minimal policy constraint field used by AVM to enforce
issuer-defined capability ceilings.

Bytes layout:

- ASCII prefix: `OREN_CERT\n2\n`
- `u8` algo (`1` = ed25519)
- `u8` flags:
  - bit0 `can_issue` (1 = may issue derived certs)
- `u64` not_before (LE) (rolling; `0` means “unset”)
- `u64` not_after  (LE) (rolling; `0` means “unset”)
- `subject_pubkey[32]`
- `issuer_keyid8[8]` = `sha256(issuer_pubkey)[:8]`
- `u64` allow_domains_mask (LE)
- `sig[64]` ed25519 signature over `SHA256(cert_body_no_sig)`

Semantics of `allow_domains_mask` (rolling):

- The mask is an AVM native domain allowlist (bit `n` corresponds to domain `n`).
- `0` means **inherit** the issuer’s effective mask (so leaf certs can omit and inherit org policy).
- Non-zero must be a **subset** of the issuer’s effective mask.
- The leaf’s effective allow_domains_mask is computed by flowing root → … → leaf:
  - root anchor implies an issuer mask of `~0` (“all allowed”)
  - per cert: `effective = issuer_effective` if mask==0, else `issuer_effective & mask`
- AVM treats an effective mask of `~0` as “unconstrained” and reports it as `0` in tooling outputs.

Domain name mapping (for human-facing tooling) matches AVM’s `OREN_CAP_ALLOW_DOMAINS` parser:

- `CORE` = bit0
- `FS` = bit1
- `TIME` = bit2
- `RNG` = bit3
- `NET` = bit4
- `PROC` = bit5
- `EXIT` = bit6
- `ENV` = bit7
- `AVM` = bit8

## Verification algorithm (AVM)

Given:

- trusted root pubkey `root_pk`
- parsed cert chain `certs[0..n-1]` (leaf-first)
- `.obc` signature payload `OREN_SIG` (signature + keyid)

Steps:

1) For each cert `i`:
   - `issuer_pk` = `certs[i+1].subject_pubkey` if `i+1 < n`, else `root_pk`
   - verify `issuer_keyid8 == sha256(issuer_pk)[:8]`
   - verify ed25519(`issuer_pk`, `SHA256(cert_body_no_sig)`, `sig`)
   - if `i+1 < n` then require `certs[i+1].can_issue == 1`
2) Leaf public key = `certs[0].subject_pubkey`
3) Require `.obc` signature keyid matches leaf keyid
4) Verify `.obc` signature with leaf pubkey
5) If leaf effective `allow_domains_mask != 0`, scan `.obc` bytecode to compute `used_domains_mask` and
   require `(used_domains_mask & ~allow_domains_mask) == 0`.

## Status

Rolling v0 implementation:

- AVM host verification supports:
  - `--require-sig` (allow root-sign or delegated leaf-sign)
  - `--require-cert-chain` (delegated leaf-sign only; requires `OREN_CERTS`)
- Tooling:
  - `orensign issue-cert ...` issues a cert from an issuer key
  - `orensign sign-obc --cert ...` embeds a single-cert chain and signs `.obc`

Future work:

- expand constraints in certs (package namespaces/import allowlists, network policy, issuer metadata)
- add revocation/rotation story (key id lists)
- add timestamp/expiry enforcement in deterministic settings
