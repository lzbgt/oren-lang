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

## Artifact Signature Model (Rolling v0)

We define a signature payload stored inside `.obc` as an unused `BYTES` constant:

- prefix: `OREN_SIG\n1\n`
- payload: algorithm id + key id + signature bytes

The signature covers a canonical hash of the `.obc` **excluding** any `OREN_SIG\n1\n` constants.

Rationale:

- `.obc` can embed metadata constants (OREN_META, OREN_OBX). We must avoid circular signing.
- The AVM must be able to verify with only `.obc` bytes (self-contained distribution).

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

## Key Handling

- Root private key: stored in `../oren-ca/` only (never in-repo).
- Root public key: embedded in AVM builds or passed explicitly for verification.
- Key rotation: supported by “key id” in the signature payload; AVM can accept a set of trusted pubkeys.

## Related Docs

- Multiverse requirements: `docs/AVM_MULTIVERSE.md`
- `.obc` module linking (OBX): `docs/OBC_MODULE_LINKING.md`
- `.obc` format and metadata conventions: `docs/AVM_SPEC.md`

