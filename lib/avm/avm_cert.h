#ifndef AVM_CERT_H
#define AVM_CERT_H

#include <stddef.h>
#include <stdint.h>

// Rolling certificate model for delegated signing keys (app-store direction).
//
// - Each certificate is a fixed-format binary blob with prefix "OREN_CERT\n{ver}\n"
//   - v1: minimal delegation fields
//   - v2: adds a simple policy constraint field (allow_domains_mask)
// - A cert chain is embedded in `.obc` as an unused BYTES constant with prefix "OREN_CERTS\n1\n"
//
// This module verifies:
// - signatures on certificates (ed25519 over SHA-256 hash of cert body)
// - issuer->subject chaining (leaf -> ... -> root)
// - delegation flag enforcement (`can_issue`)
//
// The root public key is supplied by the caller (trusted anchor).

typedef struct {
    uint8_t version;   // 1 or 2
    uint8_t algo;      // 1 = ed25519
    uint8_t flags;     // bit0 = can_issue
    uint64_t not_before_u64; // reserved (0 = unset)
    uint64_t not_after_u64;  // reserved (0 = unset)
    uint8_t subject_pubkey[32];
    uint8_t issuer_keyid8[8]; // sha256(issuer_pubkey)[:8]
    // v2: constraint on AVM native domains (u64 bitmask).
    // Semantics (rolling):
    // - 0 means "inherit issuer's effective mask" (so leaf can omit and just inherit org policy).
    // - Non-zero must be a subset of the issuer's effective mask.
    uint64_t allow_domains_mask_u64;
    uint8_t sig[64];          // ed25519 signature over hash(cert_body_no_sig)
} AvmCert;

// Parse a single cert blob (v1 or v2). Returns 1 on success.
int avm_cert_parse(const uint8_t* cert_bytes, size_t cert_len, AvmCert* out, char* err, size_t err_cap);

// Verify a cert chain (leaf-first order). Returns 1 on success.
//
// out_effective_allow_domains_mask_u64:
// - If non-NULL, receives the leaf's effective allow_domains_mask after inheritance / subset checks.
// - Value 0 means "unconstrained" (equivalent to ~0).
int avm_cert_chain_verify_leaf_first_ex(
    const uint8_t* root_pubkey32,
    const uint8_t* certs_blob,
    size_t certs_len,
    uint8_t out_leaf_pubkey32[32],
    uint64_t* out_effective_allow_domains_mask_u64,
    char* err,
    size_t err_cap
);

// Back-compat wrapper (no constraints output).
int avm_cert_chain_verify_leaf_first(const uint8_t* root_pubkey32, const uint8_t* certs_blob, size_t certs_len, uint8_t out_leaf_pubkey32[32], char* err, size_t err_cap);

#endif
