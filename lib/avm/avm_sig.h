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

// Verify signature using an embedded cert chain (OREN_CERTS) delegated by a trusted root.
//
// If require_chain==1, the `.obc` must contain an OREN_CERTS chain and the signature must match the leaf cert.
// If require_chain==0, falls back to direct-root signature verification when no chain is present.
int avm_obc_verify_signature_with_chain(const uint8_t* data, size_t len, const uint8_t* trusted_root_pubkey_32, int require_chain, char* err, size_t err_cap);

#endif
