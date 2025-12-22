#ifndef AVM_CERT_H
#define AVM_CERT_H

#include <stddef.h>
#include <stdint.h>

// Rolling certificate model for delegated signing keys (app-store direction).
//
// - Each certificate is a fixed-format binary blob with prefix "OREN_CERT\n1\n"
// - A cert chain is embedded in `.obc` as an unused BYTES constant with prefix "OREN_CERTS\n1\n"
//
// This module verifies:
// - signatures on certificates (ed25519 over SHA-256 hash of cert body)
// - issuer->subject chaining (leaf -> ... -> root)
// - delegation flag enforcement (`can_issue`)
//
// The root public key is supplied by the caller (trusted anchor).

typedef struct {
    uint8_t algo;      // 1 = ed25519
    uint8_t flags;     // bit0 = can_issue
    uint64_t not_before_u64; // reserved (0 = unset)
    uint64_t not_after_u64;  // reserved (0 = unset)
    uint8_t subject_pubkey[32];
    uint8_t issuer_keyid8[8]; // sha256(issuer_pubkey)[:8]
    uint8_t sig[64];          // ed25519 signature over hash(cert_body_no_sig)
} AvmCertV1;

// Parse a single cert blob. Returns 1 on success.
int avm_cert_parse_v1(const uint8_t* cert_bytes, size_t cert_len, AvmCertV1* out, char* err, size_t err_cap);

// Verify a cert chain (leaf-first order). Returns 1 on success.
int avm_cert_chain_verify_leaf_first(const uint8_t* root_pubkey32, const uint8_t* certs_blob, size_t certs_len, uint8_t out_leaf_pubkey32[32], char* err, size_t err_cap);

#endif

