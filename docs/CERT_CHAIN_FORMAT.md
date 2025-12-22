# Delegated Signing Certificates (OREN_CERTS) — Rolling

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

## Status

Rolling v0 implementation:

- AVM host verification supports:
  - `--require-sig` (allow root-sign or delegated leaf-sign)
  - `--require-cert-chain` (delegated leaf-sign only; requires `OREN_CERTS`)
- Tooling:
  - `orensign issue-cert ...` issues a cert from an issuer key
  - `orensign sign-obc --cert ...` embeds a single-cert chain and signs `.obc`

Future work:

- add constraints in certs (policy allowlists, package namespaces)
- add revocation/rotation story (key id lists)
- add timestamp/expiry enforcement in deterministic settings
