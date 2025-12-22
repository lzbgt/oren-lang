# AVM Anti-Tamper / Anti-Hack at Startup (Rolling)

This doc discusses whether AVM should verify its own integrity at startup (anti-tamper), and what it can
and cannot realistically defend against.

The key question:

> “What if a hacker replaced the AVM binary and also replaced the embedded root public key / verification code?”

## Threat levels (be explicit)

There are multiple “attacker strengths”:

1) **Artifact tampering in transit / at rest**
   - attacker can modify downloaded `.obc` / `.obx` / manifests
   - attacker cannot replace the AVM binary installed on the machine

2) **Local filesystem tampering (no kernel/root)**
   - attacker can modify files in user-writable directories
   - attacker cannot modify system-protected binaries or bypass OS protections

3) **Local machine compromise (root / kernel / debugger)**
   - attacker can replace `/path/to/avm`, patch it on disk, inject code at runtime,
     hook syscalls, change environment, etc.

The AVM signature model (Root CA → org → dev cert chain) is designed primarily for (1) and (2).
For (3), “self-checking” is fundamentally limited (see below).

## What AVM already defends (and how)

- **`.obc` provenance**: AVM verifies `OREN_SIG\n1\n` and optionally `OREN_CERTS\n1\n` before running artifacts.
  - The trust anchor is the **trusted root public key** (embedded or provided externally).
  - If the root public key is trustworthy, tampered artifacts are rejected.

## The hard truth: self-checking cannot create trust from nothing

If the attacker can replace the AVM binary, they can replace:

- the embedded root public key
- the signature verifier implementation
- the startup “self-check” routine itself

So AVM **cannot** “prove its own correctness” to itself if the attacker controls the executable.

This is a classical bootstrapping problem:

- A program cannot securely verify itself without an external trusted anchor.

Therefore, anti-tamper at startup is only meaningful when combined with an *external* trust boundary:

- OS code signing / notarization (macOS)
- secure boot + measured boot (TPM) (Linux/Windows)
- hardware attestation / enclave / TPM quotes
- reproducible build + external hash pinning

## Recommended trust anchors (practical)

### A) OS code signing (macOS-first)

You already use codesigning for `oren` builds. Extending that mindset to AVM:

- distribute AVM as a codesigned binary
- optionally require notarization for “production distribution” builds

If AVM is codesigned and installed into a protected location, a simple “replace avm” attack becomes harder.

AVM startup “self-check” can then become:

- “verify that the binary is codesigned by expected team id” (platform API check)
- “verify we are not running under a debugger” (anti-debug; mostly a speed bump)

This provides “tamper evidence” under attacker levels (1) and (2), but does not defeat root compromise.

### B) External root pubkey pinning

For deployments that want maximum control:

- do not embed a root pubkey in AVM
- instead pass `--trusted-pubkey` (or a set) via a deployment mechanism the attacker cannot change
  - system policy file in a protected directory
  - mobile/desktop MDM configuration
  - container image digest / Kubernetes secret (still has its own trust chain)

Then “replace AVM and also replace embedded pubkey” is less meaningful because the trust anchor is outside the binary.

### C) Measured boot / attestation (future)

To defend against attacker level (3), you need attestation:

- boot measures AVM binary hash into TPM PCRs
- a remote verifier checks PCR quote + policy
- only then is AVM trusted to run sensitive workloads

This is bigger than rolling-mode AVM right now, but is the “correct” direction if you want production-grade anti-tamper.

## What AVM can do at startup (useful, limited)

### 1) “Self-hash” (weak but cheap)

AVM can compute a hash of its own on-disk image and log it, or compare to an expected hash.

Limitation:

- if the attacker can patch the binary, they can patch the expected hash or the hashing code.

Still useful as:

- diagnostics / telemetry (“what exact AVM build is running?”)
- accidental corruption detection

### 2) Verify embedded root pubkey is non-zero and matches a build-time constant

This is only meaningful when combined with external constraints (codesign / immutable deployment).
Otherwise the attacker replaces both.

### 3) Anti-debug / anti-hook checks (speed bumps)

Examples:

- detect debugger attach
- detect LD_PRELOAD / DYLD injection patterns
- detect writable+executable memory mappings

Limitations:

- easy to bypass for a motivated attacker
- can cause false positives and harm developer UX

These are generally not recommended as default policy in rolling mode; they can exist behind a “hardened mode”.

## Answer to “what if hacker replaced the certs and sig?”

### If they only replace the `.obc`’s certs/sig (OREN_CERTS/OREN_SIG)

AVM rejects it because:

- signature check fails, unless attacker has a valid delegated signing key.

### If they replace the AVM binary to trust their own key

Then all bets are off unless you have an external trust boundary:

- OS code signing / secure boot / attestation / protected config pinning

This is not unique to Oren: it is the same for basically all verifiers (package managers, runtimes, etc).

## Rolling roadmap recommendation

P0 (now):

- keep artifact signature verification as the primary enforcement boundary
- document the bootstrapping limitation clearly (this doc)
- add optional “diagnostic self-hash” mode (not a security promise)

P1 (soon):

- ship codesigned AVM builds; consider a “release” build pipeline step that signs AVM
- allow a trusted pubkey *set* provided externally (rotation story)

P2 (later):

- measured boot / attestation integration for production deployments that require it

