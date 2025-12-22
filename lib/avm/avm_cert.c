#include "avm_cert.h"

#include "sha256.h"

#include <stdio.h>
#include <string.h>

#include "../../third_party/tweetnacl/tweetnacl.h"

static const char* CERT_PREFIX = "OREN_CERT\n1\n";
static const size_t CERT_PREFIX_LEN = 12;
static const char* CERTS_PREFIX = "OREN_CERTS\n1\n";
static const size_t CERTS_PREFIX_LEN = 13;

static void err_set(char* err, size_t cap, const char* msg) {
    if (!err || cap == 0) return;
    if (!msg) msg = "cert verify failed";
    snprintf(err, cap, "%s", msg);
}

static uint16_t u16_le(const uint8_t* p) { return (uint16_t)p[0] | ((uint16_t)p[1] << 8); }
static uint64_t u64_le(const uint8_t* p) {
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v |= ((uint64_t)p[i]) << (i * 8);
    return v;
}

static int starts_with(const uint8_t* b, size_t blen, const char* pref, size_t plen) {
    if (!b || !pref) return 0;
    if (blen < plen) return 0;
    return memcmp(b, pref, plen) == 0;
}

static void sha256_bytes_simple(const uint8_t* data, size_t len, uint8_t out[32]) {
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    if (data && len > 0) avm_sha256_update(&h, data, len);
    avm_sha256_final(&h, out);
}

static int ed25519_verify_hash_sig(const uint8_t pubkey[32], const uint8_t hash[32], const uint8_t sig[64]) {
    // TweetNaCl verify pattern: crypto_sign_open over (sig || msg) -> yields msg.
    unsigned char sm[64 + 32];
    unsigned char m[64 + 32];
    unsigned long long mlen = 0;
    memcpy(sm, sig, 64);
    memcpy(sm + 64, hash, 32);
    if (crypto_sign_open(m, &mlen, sm, sizeof(sm), pubkey) != 0) return 0;
    if (mlen != 32) return 0;
    return memcmp(m, hash, 32) == 0;
}

int avm_cert_parse_v1(const uint8_t* cert_bytes, size_t cert_len, AvmCertV1* out, char* err, size_t err_cap) {
    if (!cert_bytes || !out) { err_set(err, err_cap, "nil cert"); return 0; }
    if (!starts_with(cert_bytes, cert_len, CERT_PREFIX, CERT_PREFIX_LEN)) { err_set(err, err_cap, "bad cert prefix"); return 0; }
    size_t pos = CERT_PREFIX_LEN;
    // Fixed layout after prefix:
    // algo(1) flags(1) not_before(8) not_after(8) subject_pk(32) issuer_keyid8(8) sig(64)
    if (cert_len < CERT_PREFIX_LEN + 1 + 1 + 8 + 8 + 32 + 8 + 64) {
        err_set(err, err_cap, "cert too short");
        return 0;
    }
    out->algo = cert_bytes[pos++];
    out->flags = cert_bytes[pos++];
    out->not_before_u64 = u64_le(cert_bytes + pos);
    pos += 8;
    out->not_after_u64 = u64_le(cert_bytes + pos);
    pos += 8;
    memcpy(out->subject_pubkey, cert_bytes + pos, 32);
    pos += 32;
    memcpy(out->issuer_keyid8, cert_bytes + pos, 8);
    pos += 8;
    memcpy(out->sig, cert_bytes + pos, 64);
    pos += 64;
    (void)pos;
    if (out->algo != 1) { err_set(err, err_cap, "unsupported cert algo"); return 0; }
    return 1;
}

int avm_cert_chain_verify_leaf_first(const uint8_t* root_pubkey32, const uint8_t* certs_blob, size_t certs_len, uint8_t out_leaf_pubkey32[32], char* err, size_t err_cap) {
    if (!root_pubkey32) { err_set(err, err_cap, "missing root pubkey"); return 0; }
    if (!certs_blob || certs_len == 0) { err_set(err, err_cap, "missing cert chain"); return 0; }
    if (!starts_with(certs_blob, certs_len, CERTS_PREFIX, CERTS_PREFIX_LEN)) { err_set(err, err_cap, "bad certs prefix"); return 0; }
    size_t pos = CERTS_PREFIX_LEN;
    if (pos + 2 > certs_len) { err_set(err, err_cap, "truncated certs header"); return 0; }
    uint16_t count = u16_le(certs_blob + pos);
    pos += 2;
    if (count == 0) { err_set(err, err_cap, "empty cert chain"); return 0; }
    // Parse all cert spans into a small table (count is expected small).
    const uint8_t* cert_ptrs[32];
    size_t cert_lens[32];
    if (count > 32) { err_set(err, err_cap, "cert chain too long"); return 0; }
    for (uint16_t i = 0; i < count; i++) {
        if (pos + 2 > certs_len) { err_set(err, err_cap, "truncated cert length"); return 0; }
        uint16_t clen = u16_le(certs_blob + pos);
        pos += 2;
        if (pos + clen > certs_len) { err_set(err, err_cap, "truncated cert bytes"); return 0; }
        cert_ptrs[i] = certs_blob + pos;
        cert_lens[i] = (size_t)clen;
        pos += clen;
    }

    AvmCertV1 certs[32];
    for (uint16_t i = 0; i < count; i++) {
        if (!avm_cert_parse_v1(cert_ptrs[i], cert_lens[i], &certs[i], err, err_cap)) return 0;
    }

    // Verify chain leaf-first:
    // - cert[i] is issued by cert[i+1].subject_pubkey (or root pubkey for last).
    // - issuer must have can_issue for non-root issuances (i+1 exists).
    for (uint16_t i = 0; i < count; i++) {
        const uint8_t* issuer_pk = NULL;
        uint8_t issuer_keyid[32];
        if (i + 1 < count) {
            // require issuer can_issue
            if ((certs[i+1].flags & 0x01) == 0) { err_set(err, err_cap, "issuer not allowed to issue"); return 0; }
            issuer_pk = certs[i+1].subject_pubkey;
        } else {
            issuer_pk = root_pubkey32;
        }

        sha256_bytes_simple(issuer_pk, 32, issuer_keyid);
        if (memcmp(certs[i].issuer_keyid8, issuer_keyid, 8) != 0) { err_set(err, err_cap, "issuer keyid mismatch"); return 0; }

        // Verify signature over SHA256(cert_body_no_sig).
        // cert_body_no_sig is the cert bytes excluding the last 64 bytes (signature).
        size_t body_len = cert_lens[i];
        if (body_len < 64) { err_set(err, err_cap, "cert too short"); return 0; }
        body_len -= 64;
        uint8_t body_hash[32];
        sha256_bytes_simple(cert_ptrs[i], body_len, body_hash);
        if (!ed25519_verify_hash_sig(issuer_pk, body_hash, certs[i].sig)) { err_set(err, err_cap, "cert signature invalid"); return 0; }
    }

    // Leaf pubkey is cert[0].subject_pubkey.
    if (out_leaf_pubkey32) memcpy(out_leaf_pubkey32, certs[0].subject_pubkey, 32);
    return 1;
}
