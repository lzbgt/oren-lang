// Rolling: AVM root trust anchor (public key only).
//
// This file is intentionally safe to commit: it contains a public key, not secrets.
// The corresponding private key MUST live outside the repo (recommended: ../oren-ca/).
//
// Default is all-zero (no embedded trust). In this mode:
// - callers must provide a trusted pubkey explicitly when requiring signatures.
//
// To embed a real root key:
// - generate keys under ../oren-ca/
// - write a 32-byte ed25519 public key into AVM_ROOT_ED25519_PUBKEY_BYTES
//
static const unsigned char AVM_ROOT_ED25519_PUBKEY_BYTES[32] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
};

