// Rolling: AVM root trust anchors (public keys only).
//
// This file is intentionally safe to commit: it contains public keys, not secrets.
// The corresponding private keys MUST live outside the repo (recommended: ../oren-ca/).
//
// Design goals:
// - Embed trust anchors for end-user distributions (no CLI flags needed).
// - Support root rotation by embedding a *set* of trusted roots.
//
// Default is "no embedded trust": AVM_TRUSTED_ROOT_PUBKEYS_COUNT = 0.
// In this mode, callers must provide trusted pubkey(s) explicitly (CLI/env) when
// requiring signatures.
//
// To embed real root key(s):
// - generate keys under ../oren-ca/
// - set AVM_TRUSTED_ROOT_PUBKEYS_COUNT to 1..AVM_TRUSTED_ROOT_PUBKEYS_SLOTS
// - replace the bytes in AVM_TRUSTED_ROOT_PUBKEY{0,1,2,3}_BYTES accordingly
//
// NOTE: `*_COUNT` controls which keys are considered trusted; keys beyond COUNT are ignored.

// Maximum number of embedded trusted roots we support in rolling mode.
#define AVM_TRUSTED_ROOT_PUBKEYS_SLOTS 4

static const unsigned char AVM_TRUSTED_ROOT_PUBKEY0_BYTES[32] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
};
static const unsigned char AVM_TRUSTED_ROOT_PUBKEY1_BYTES[32] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
};
static const unsigned char AVM_TRUSTED_ROOT_PUBKEY2_BYTES[32] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
};
static const unsigned char AVM_TRUSTED_ROOT_PUBKEY3_BYTES[32] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
};

static const unsigned char* const AVM_TRUSTED_ROOT_PUBKEYS[AVM_TRUSTED_ROOT_PUBKEYS_SLOTS] = {
    AVM_TRUSTED_ROOT_PUBKEY0_BYTES,
    AVM_TRUSTED_ROOT_PUBKEY1_BYTES,
    AVM_TRUSTED_ROOT_PUBKEY2_BYTES,
    AVM_TRUSTED_ROOT_PUBKEY3_BYTES,
};

// Default: no embedded trust anchors (safe for dev builds).
static const size_t AVM_TRUSTED_ROOT_PUBKEYS_COUNT = 0;
