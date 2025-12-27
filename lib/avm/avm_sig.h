#ifndef AVM_SIG_H
#define AVM_SIG_H

#include <stddef.h>
#include <stdint.h>

// Verify an `.obc` signature (rolling).
//
// Signature representation:
// - stored as an unused BYTES constant with prefix "OREN_SIG\n1\n"
// - signature covers SHA-256 hash of canonical `.obc` bytes with all OREN_SIG constants removed
//
// trusted_pubkey_32:
// - if non-NULL: must point to 32-byte ed25519 pubkey
// - if NULL: uses embedded root pubkey if present (see avm_root_pubkey.inc)
//
// Returns 1 on success, 0 on failure. On failure, writes a human-readable error to `err` if provided.
int avm_obc_verify_signature(const uint8_t* data, size_t len, const uint8_t* trusted_pubkey_32, char* err, size_t err_cap);

// Returns 1 if a non-zero embedded root pubkey is present.
int avm_has_embedded_root_pubkey(void);

// Verify signature (and optional cert chain) against *any* trusted root pubkey.
//
// trusted_root_pubkeys_32:
// - if non-NULL and trusted_root_pubkeys_count>0, treat it as a packed array of
//   `trusted_root_pubkeys_count` pubkeys, each 32 bytes (ed25519 public key).
// - embedded trusted roots (from avm_root_pubkey.inc) are also tried.
//
// require_chain:
// - if 1: OREN_CERTS must be present and valid (root -> ... -> leaf).
// - if 0: absence of OREN_CERTS falls back to direct-root signature verification.
int avm_obc_verify_signature_with_chain_any(
    const uint8_t* data,
    size_t len,
    const uint8_t* trusted_root_pubkeys_32,
    size_t trusted_root_pubkeys_count,
    int require_chain,
    char* err,
    size_t err_cap
);

// Same as avm_obc_verify_signature_with_chain_any, but also returns the effective
// allow_domains_mask computed from the leaf cert (v2) if a chain is present.
//
// out_effective_allow_domains_mask_u64:
// - If non-NULL and a chain is present and valid, receives a u64 bitmask.
// - 0 means "unconstrained" (equivalent to ~0).
// - If no chain is present (and require_chain==0), returns 0.
int avm_obc_verify_signature_with_chain_any_ex(
    const uint8_t* data,
    size_t len,
    const uint8_t* trusted_root_pubkeys_32,
    size_t trusted_root_pubkeys_count,
    int require_chain,
    uint64_t* out_effective_allow_domains_mask_u64,
    char* err,
    size_t err_cap
);

// Verify signature using an embedded cert chain (OREN_CERTS) delegated by a trusted root.
//
// If require_chain==1, the `.obc` must contain an OREN_CERTS chain and the signature must match the leaf cert.
// If require_chain==0, falls back to direct-root signature verification when no chain is present.
int avm_obc_verify_signature_with_chain(
    const uint8_t* data,
    size_t len,
    const uint8_t* trusted_root_pubkey_32,
    int require_chain,
    char* err,
    size_t err_cap
);

#endif
