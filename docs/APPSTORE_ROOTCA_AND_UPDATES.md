# AVM App-Store Model: Root CA, Signed OBC, and Multiverse Updates (Rolling)

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

Spec: `docs/CERT_CHAIN_FORMAT.md`.

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

- Multiverse requirements: `docs/AVM_MULTIVERSE.md`
- `.obc` module linking (OBX): `docs/OBC_MODULE_LINKING.md`
- `.obc` format and metadata conventions: `docs/AVM_SPEC.md`
- Delegated signing cert chains: `docs/CERT_CHAIN_FORMAT.md`
