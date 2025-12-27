#include "avm_sig.h"

#include "avm.h"
#include "sha256.h"
#include "avm_cert.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../../third_party/tweetnacl/tweetnacl.h"

// Embedded root pubkey (public only; safe).
#include "avm_root_pubkey.inc"

static const char* SIG_PREFIX = "OREN_SIG\n1\n";
static const size_t SIG_PREFIX_LEN = 11;
static const char* CERTS_PREFIX = "OREN_CERTS\n1\n";
static const size_t CERTS_PREFIX_LEN = 13;

static int is_all_zero_32(const unsigned char k[32]) {
    unsigned char acc = 0;
    for (int i = 0; i < 32; i++) acc |= k[i];
    return acc == 0;
}

static const unsigned char* avm_first_embedded_root_pubkey(void) {
    // Returns the first non-zero embedded pubkey among the active set, or NULL.
    if (AVM_TRUSTED_ROOT_PUBKEYS_COUNT == 0) return NULL;
    size_t n = AVM_TRUSTED_ROOT_PUBKEYS_COUNT;
    if (n > (size_t)AVM_TRUSTED_ROOT_PUBKEYS_SLOTS) n = (size_t)AVM_TRUSTED_ROOT_PUBKEYS_SLOTS;
    for (size_t i = 0; i < n; i++) {
        const unsigned char* pk = AVM_TRUSTED_ROOT_PUBKEYS[i];
        if (!pk) continue;
        if (!is_all_zero_32(pk)) return pk;
    }
    return NULL;
}

int avm_has_embedded_root_pubkey(void) {
    return avm_first_embedded_root_pubkey() != NULL;
}

static void err_set(char* err, size_t cap, const char* msg) {
    if (!err || cap == 0) return;
    if (!msg) msg = "signature verify failed";
    snprintf(err, cap, "%s", msg);
}

static uint16_t u16_le(const uint8_t* p) { return (uint16_t)p[0] | ((uint16_t)p[1] << 8); }
static uint32_t u32_le(const uint8_t* p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }

static int bytes_starts_with(const uint8_t* b, size_t blen, const char* pref) {
    size_t plen = strlen(pref);
    if (!b || !pref) return 0;
    if (blen < plen) return 0;
    return memcmp(b, pref, plen) == 0;
}

static int avm_obc_verify_signature_with_chain_ex(
    const uint8_t* data,
    size_t len,
    const uint8_t* trusted_root_pubkey_32,
    int require_chain,
    uint64_t* out_effective_allow_domains_mask_u64,
    char* err,
    size_t err_cap
);

static int obc_scan_used_domains_mask(const uint8_t* data, size_t len, uint64_t* used_domains_mask_out, char* err, size_t err_cap) {
    if (!used_domains_mask_out) { err_set(err, err_cap, "nil used_domains_mask"); return 0; }
    *used_domains_mask_out = 0;
    if (!data || len < 4) { err_set(err, err_cap, "obc too short"); return 0; }
    if (data[0] != 0xCD || data[1] != 0x0E) { err_set(err, err_cap, "bad obc magic"); return 0; }

    size_t pos = 2;
    if (pos + 2 > len) { err_set(err, err_cap, "truncated const count"); return 0; }
    uint16_t n_consts = u16_le(data + pos);
    pos += 2;

    // Skip constant pool to find code bytes start.
    for (uint16_t i = 0; i < n_consts; i++) {
        if (pos >= len) { err_set(err, err_cap, "truncated const pool"); return 0; }
        uint8_t typ = data[pos++];
        if (typ == 0) {
            // nil
        } else if (typ == 1) {
            if (pos + 8 > len) { err_set(err, err_cap, "truncated int const"); return 0; }
            pos += 8;
        } else if (typ == 2) {
            if (pos + 1 > len) { err_set(err, err_cap, "truncated bool const"); return 0; }
            pos += 1;
        } else if (typ == 3) {
            if (pos + 8 > len) { err_set(err, err_cap, "truncated float const"); return 0; }
            pos += 8;
        } else if (typ == 4) {
            if (pos + 2 > len) { err_set(err, err_cap, "truncated string const"); return 0; }
            uint16_t slen = u16_le(data + pos);
            pos += 2;
            if (pos + slen > len) { err_set(err, err_cap, "truncated string payload"); return 0; }
            pos += slen;
        } else if (typ == 8) {
            if (pos + 4 > len) { err_set(err, err_cap, "truncated bytes const"); return 0; }
            uint32_t blen = u32_le(data + pos);
            pos += 4;
            if (pos + blen > len) { err_set(err, err_cap, "truncated bytes payload"); return 0; }
            pos += blen;
        } else {
            err_set(err, err_cap, "unknown const tag");
            return 0;
        }
    }

    if (pos > len) { err_set(err, err_cap, "bad code pos"); return 0; }
    const uint8_t* code = data + pos;
    size_t code_len = len - pos;

    uint64_t domains = 0;
    size_t pc = 0;
    while (pc < code_len) {
        uint8_t op = code[pc];
        size_t ins_len = 1;
        // Keep in sync with main.c policy_scan_program (only these opcodes have operands today).
        if (op == 0x02) ins_len = 3;
        else if (op == 0x04 || op == 0x05) ins_len = 2;
        else if (op == 0x52 || op == 0x53) ins_len = 3;
        else if (op == 0x06 || op == 0x07) ins_len = 3;
        else if (op == 0x30 || op == 0x31) ins_len = 3;
        else if (op == 0x4E || op == 0x4F) ins_len = 5;
        else if (op == 0x38) ins_len = 4;
        else if (op == 0x50) ins_len = 6;
        else if (op == 0x3A) ins_len = 4;
        else if (op == 0x3B) ins_len = 5;
        else if (op == 0x3C) ins_len = 3;
        else if (op == 0x51) ins_len = 5;
        else if (op == 0x3D) ins_len = 2;
        else if (op == 0x44) ins_len = 2;
        else if (op == 0x3E) ins_len = 2;
        else if (op == 0x3F) ins_len = 2;
        else if (op == 0x40 || op == 0x41) ins_len = 3;

        if (pc + ins_len > code_len) { err_set(err, err_cap, "truncated opcode"); return 0; }

        if (op == 0x3A) { // CALL_NATIVE u16_id u8_nargs
            uint16_t id = (uint16_t)code[pc + 1] | ((uint16_t)code[pc + 2] << 8);
            uint8_t dom = 0;
            uint16_t capop = 0;
            avm_legacy_native_to_domop(id, &dom, &capop);
            domains |= (1ULL << (dom & 63));
        } else if (op == 0x3B) { // CALL_NATIVE2 u8_domain u16_op u8_nargs
            uint8_t dom = code[pc + 1];
            uint16_t capop = (uint16_t)code[pc + 2] | ((uint16_t)code[pc + 3] << 8);
            if (dom == 0) {
                uint8_t nd = 0;
                uint16_t nop = capop;
                avm_legacy_native_to_domop(capop, &nd, &nop);
                if (nd != 0) dom = nd;
            }
            domains |= (1ULL << (dom & 63));
        }

        pc += ins_len;
    }

    *used_domains_mask_out = domains;
    return 1;
}

// Compute canonical hash:
// magic + u16 kept_const_count + all kept const raw bytes + code bytes
// where kept consts exclude signature/metadata constants:
// - OREN_SIG (signature payload)
// - OREN_CERTS (delegation chain payload)
static int hash_obc_canonical_no_sig(
    const uint8_t* data,
    size_t len,
    uint8_t out_hash[32],
    uint8_t out_sig[64],
    int* has_sig_out,
    uint8_t out_keyid8[8],
    const uint8_t** out_certs_payload,
    size_t* out_certs_len,
    char* err,
    size_t err_cap
) {
    if (!data || len < 4) { err_set(err, err_cap, "obc too short"); return 0; }
    if (data[0] != 0xCD || data[1] != 0x0E) { err_set(err, err_cap, "bad obc magic"); return 0; }
    size_t pos = 2;
    if (pos + 2 > len) { err_set(err, err_cap, "truncated const count"); return 0; }
    uint16_t n_consts = u16_le(data + pos);
    pos += 2;
    size_t code_pos = 0;

    // First pass: identify constant byte ranges and signature/metadata payloads.
    typedef struct { size_t start, end; int skip; } Range;
    Range* ranges = NULL;
    if (n_consts > 0) {
        ranges = (Range*)malloc(sizeof(Range) * (size_t)n_consts);
        if (!ranges) { err_set(err, err_cap, "oom"); return 0; }
    }
    int has_sig = 0;
    size_t kept = 0;
    const uint8_t* certs_payload = NULL;
    size_t certs_len = 0;

    for (uint16_t i = 0; i < n_consts; i++) {
        if (pos >= len) { free(ranges); err_set(err, err_cap, "truncated const pool"); return 0; }
        size_t start = pos;
        uint8_t typ = data[pos++];
        int skip_range = 0;
        if (typ == 0) {
            // nil
        } else if (typ == 1) {
            if (pos + 8 > len) { free(ranges); err_set(err, err_cap, "truncated int const"); return 0; }
            pos += 8;
        } else if (typ == 2) {
            if (pos + 1 > len) { free(ranges); err_set(err, err_cap, "truncated bool const"); return 0; }
            pos += 1;
        } else if (typ == 3) {
            if (pos + 8 > len) { free(ranges); err_set(err, err_cap, "truncated float const"); return 0; }
            pos += 8;
        } else if (typ == 4) {
            if (pos + 2 > len) { free(ranges); err_set(err, err_cap, "truncated string const"); return 0; }
            uint16_t slen = u16_le(data + pos);
            pos += 2;
            if (pos + slen > len) { free(ranges); err_set(err, err_cap, "truncated string payload"); return 0; }
            pos += slen;
        } else if (typ == 8) {
            if (pos + 4 > len) { free(ranges); err_set(err, err_cap, "truncated bytes const"); return 0; }
            uint32_t blen = u32_le(data + pos);
            pos += 4;
            if (pos + blen > len) { free(ranges); err_set(err, err_cap, "truncated bytes payload"); return 0; }
            const uint8_t* payload = data + pos;
            int is_sig = bytes_starts_with(payload, (size_t)blen, SIG_PREFIX);
            int is_certs = bytes_starts_with(payload, (size_t)blen, CERTS_PREFIX);
            if (is_sig) {
                // Parse payload:
                // prefix + u8 algo + u8 hash + keyid[8] + sig[64]
                if ((size_t)blen < SIG_PREFIX_LEN + 1 + 1 + 8 + 64) {
                    free(ranges);
                    err_set(err, err_cap, "sig payload too short");
                    return 0;
                }
                uint8_t algo = payload[SIG_PREFIX_LEN + 0];
                uint8_t hkind = payload[SIG_PREFIX_LEN + 1];
                if (algo != 1 || hkind != 1) {
                    free(ranges);
                    err_set(err, err_cap, "unsupported sig algo/hash");
                    return 0;
                }
                if (has_sig) {
                    free(ranges);
                    err_set(err, err_cap, "multiple signatures not allowed");
                    return 0;
                }
                memcpy(out_keyid8, payload + SIG_PREFIX_LEN + 2, 8);
                memcpy(out_sig, payload + SIG_PREFIX_LEN + 2 + 8, 64);
                has_sig = 1;
            }
            // Also capture cert-chain payload if present (optional).
            if (is_certs) {
                if (certs_payload) {
                    free(ranges);
                    err_set(err, err_cap, "multiple OREN_CERTS constants not allowed");
                    return 0;
                }
                certs_payload = payload;
                certs_len = (size_t)blen;
            }
            // Exclude signature + metadata constants from canonical bytes.
            if (is_sig || is_certs) skip_range = 1;
            pos += blen;
        } else {
            free(ranges);
            err_set(err, err_cap, "unknown const tag");
            return 0;
        }
        size_t end = pos;
        if (ranges) {
            ranges[i].start = start;
            ranges[i].end = end;
            ranges[i].skip = skip_range;
        }
        if (!skip_range) kept++;
    }
    code_pos = pos;

    // Hash canonical form.
    AvmSha256Ctx h;
    avm_sha256_init(&h);
    const uint8_t magic[2] = {0xCD, 0x0E};
    avm_sha256_update(&h, magic, 2);
    uint8_t cnt[2] = {(uint8_t)(kept & 255), (uint8_t)((kept >> 8) & 255)};
    avm_sha256_update(&h, cnt, 2);
    for (uint16_t i = 0; i < n_consts; i++) {
        if (ranges && ranges[i].skip) continue;
        if (ranges) avm_sha256_update(&h, data + ranges[i].start, ranges[i].end - ranges[i].start);
    }
    // Remaining bytes are code.
    if (code_pos <= len) avm_sha256_update(&h, data + code_pos, len - code_pos);
    avm_sha256_final(&h, out_hash);

    free(ranges);
    if (has_sig_out) *has_sig_out = has_sig;
    if (out_certs_payload) *out_certs_payload = certs_payload;
    if (out_certs_len) *out_certs_len = certs_len;
    return 1;
}

int avm_obc_verify_signature(const uint8_t* data, size_t len, const uint8_t* trusted_pubkey_32, char* err, size_t err_cap) {
    uint8_t pk[32];
    if (trusted_pubkey_32) {
        memcpy(pk, trusted_pubkey_32, 32);
    } else {
        if (!avm_has_embedded_root_pubkey()) {
            err_set(err, err_cap, "no trusted pubkey provided and no embedded root pubkey");
            return 0;
        }
        const unsigned char* emb = avm_first_embedded_root_pubkey();
        if (!emb) { err_set(err, err_cap, "no embedded root pubkey"); return 0; }
        // Historical API: pick one embedded root. For rotation, prefer *_any().
        memcpy(pk, emb, 32);
    }

    uint8_t hash[32];
    uint8_t sig[64];
    uint8_t keyid[8];
    int has_sig = 0;
    const uint8_t* certs_payload = NULL;
    size_t certs_len = 0;
    if (!hash_obc_canonical_no_sig(data, len, hash, sig, &has_sig, keyid, &certs_payload, &certs_len, err, err_cap)) return 0;
    if (!has_sig) {
        err_set(err, err_cap, "missing OREN_SIG signature");
        return 0;
    }

    // Enforce key id match for the trusted pubkey (sha256(pk)[:8]).
    uint8_t pkhash[32];
    AvmSha256Ctx hh;
    avm_sha256_init(&hh);
    avm_sha256_update(&hh, pk, 32);
    avm_sha256_final(&hh, pkhash);
    if (memcmp(keyid, pkhash, 8) != 0) {
        err_set(err, err_cap, "signature key id mismatch");
        return 0;
    }

    // Verify signature over the 32-byte hash (message = hash).
    unsigned char sm[64 + 32];
    unsigned char m[64 + 32];
    unsigned long long mlen = 0;
    memcpy(sm, sig, 64);
    memcpy(sm + 64, hash, 32);
    if (crypto_sign_open(m, &mlen, sm, sizeof(sm), pk) != 0) {
        err_set(err, err_cap, "ed25519 signature invalid");
        return 0;
    }
    if (mlen != 32 || memcmp(m, hash, 32) != 0) {
        err_set(err, err_cap, "signature message mismatch");
        return 0;
    }
    return 1;
}

int avm_obc_verify_signature_with_chain(
    const uint8_t* data,
    size_t len,
    const uint8_t* trusted_root_pubkey_32,
    int require_chain,
    char* err,
    size_t err_cap
) {
    return avm_obc_verify_signature_with_chain_ex(data, len, trusted_root_pubkey_32, require_chain, NULL, err, err_cap);
}

static int avm_obc_verify_signature_with_chain_ex(
    const uint8_t* data,
    size_t len,
    const uint8_t* trusted_root_pubkey_32,
    int require_chain,
    uint64_t* out_effective_allow_domains_mask_u64,
    char* err,
    size_t err_cap
) {
    if (!trusted_root_pubkey_32 && !avm_has_embedded_root_pubkey()) {
        err_set(err, err_cap, "missing trusted root pubkey");
        return 0;
    }
    // Historical API: if no root pubkey is provided, use the first embedded root key.
    const unsigned char* emb = avm_first_embedded_root_pubkey();
    const uint8_t* root_pk = trusted_root_pubkey_32 ? trusted_root_pubkey_32 : (const uint8_t*)emb;
    if (!root_pk) { err_set(err, err_cap, "missing trusted root pubkey"); return 0; }

    uint8_t hash[32];
    uint8_t sig[64];
    uint8_t keyid[8];
    int has_sig = 0;
    const uint8_t* certs_payload = NULL;
    size_t certs_len = 0;
    if (!hash_obc_canonical_no_sig(data, len, hash, sig, &has_sig, keyid, &certs_payload, &certs_len, err, err_cap)) return 0;
    if (!has_sig) { err_set(err, err_cap, "missing OREN_SIG signature"); return 0; }

    // If there is no cert chain, fall back to direct-root signature only when not required.
    if (!certs_payload || certs_len == 0) {
        if (require_chain) { err_set(err, err_cap, "missing OREN_CERTS chain"); return 0; }
        if (out_effective_allow_domains_mask_u64) *out_effective_allow_domains_mask_u64 = 0;
        return avm_obc_verify_signature(data, len, root_pk, err, err_cap);
    }

    // Verify cert chain, get leaf pubkey and effective policy constraints.
    uint8_t leaf_pk[32];
    uint64_t allow_mask = 0;
    if (!avm_cert_chain_verify_leaf_first_ex(root_pk, certs_payload, certs_len, leaf_pk, &allow_mask, err, err_cap)) return 0;

    // Enforce that the signature keyid matches the leaf pubkey.
    uint8_t leaf_hash[32];
    AvmSha256Ctx hh;
    avm_sha256_init(&hh);
    avm_sha256_update(&hh, leaf_pk, 32);
    avm_sha256_final(&hh, leaf_hash);
    if (memcmp(keyid, leaf_hash, 8) != 0) { err_set(err, err_cap, "sig keyid does not match leaf cert"); return 0; }

    // Verify signature with leaf pubkey.
    unsigned char sm[64 + 32];
    unsigned char m[64 + 32];
    unsigned long long mlen = 0;
    memcpy(sm, sig, 64);
    memcpy(sm + 64, hash, 32);
    if (crypto_sign_open(m, &mlen, sm, sizeof(sm), leaf_pk) != 0) {
        err_set(err, err_cap, "ed25519 signature invalid");
        return 0;
    }
    if (mlen != 32 || memcmp(m, hash, 32) != 0) {
        err_set(err, err_cap, "signature message mismatch");
        return 0;
    }

    // Enforce leaf cert allow_domains_mask (v2) against the artifact's used domains.
    // This must hold even if the host allows broader capabilities: certs are issuer policy.
    if (allow_mask != 0) {
        uint64_t used_domains_mask = 0;
        if (!obc_scan_used_domains_mask(data, len, &used_domains_mask, err, err_cap)) return 0;
        if ((used_domains_mask & ~allow_mask) != 0) {
            char msg[128];
            snprintf(msg, sizeof(msg), "cert policy failed: used_domains_mask=0x%016llx not_subset_of allow_domains_mask=0x%016llx",
                     (unsigned long long)used_domains_mask,
                     (unsigned long long)allow_mask);
            err_set(err, err_cap, msg);
            return 0;
        }
    }

    if (out_effective_allow_domains_mask_u64) *out_effective_allow_domains_mask_u64 = allow_mask;
    return 1;
}

int avm_obc_verify_signature_with_chain_any(
    const uint8_t* data,
    size_t len,
    const uint8_t* trusted_root_pubkeys_32,
    size_t trusted_root_pubkeys_count,
    int require_chain,
    char* err,
    size_t err_cap
) {
    return avm_obc_verify_signature_with_chain_any_ex(
        data,
        len,
        trusted_root_pubkeys_32,
        trusted_root_pubkeys_count,
        require_chain,
        NULL,
        err,
        err_cap
    );
}

int avm_obc_verify_signature_with_chain_any_ex(
    const uint8_t* data,
    size_t len,
    const uint8_t* trusted_root_pubkeys_32,
    size_t trusted_root_pubkeys_count,
    int require_chain,
    uint64_t* out_effective_allow_domains_mask_u64,
    char* err,
    size_t err_cap
) {
    // Try CLI/env-provided keys first (if any), then embedded roots.
    //
    // This enables root rotation by allowing a set of roots to be trusted at once.
    // A signature may match any one of them.
    char last_err[256];
    last_err[0] = 0;

    if (trusted_root_pubkeys_32 && trusted_root_pubkeys_count > 0) {
        for (size_t i = 0; i < trusted_root_pubkeys_count; i++) {
            const uint8_t* pk = trusted_root_pubkeys_32 + i * 32;
            uint64_t allow_mask = 0;
            if (!avm_obc_verify_signature_with_chain_ex(data, len, pk, require_chain, &allow_mask, last_err, sizeof(last_err))) {
                continue;
            }
            if (out_effective_allow_domains_mask_u64) *out_effective_allow_domains_mask_u64 = allow_mask;
            return 1;
        }
    }

    if (AVM_TRUSTED_ROOT_PUBKEYS_COUNT > 0) {
        size_t n = AVM_TRUSTED_ROOT_PUBKEYS_COUNT;
        if (n > (size_t)AVM_TRUSTED_ROOT_PUBKEYS_SLOTS) n = (size_t)AVM_TRUSTED_ROOT_PUBKEYS_SLOTS;
        for (size_t i = 0; i < n; i++) {
            const unsigned char* pk = AVM_TRUSTED_ROOT_PUBKEYS[i];
            if (!pk) continue;
            if (is_all_zero_32(pk)) continue;
            uint64_t allow_mask = 0;
            if (!avm_obc_verify_signature_with_chain_ex(data, len, pk, require_chain, &allow_mask, last_err, sizeof(last_err))) {
                continue;
            }
            if (out_effective_allow_domains_mask_u64) *out_effective_allow_domains_mask_u64 = allow_mask;
            return 1;
        }
    }

    // No match. Report best-effort error.
    if ((!trusted_root_pubkeys_32 || trusted_root_pubkeys_count == 0) && !avm_has_embedded_root_pubkey()) {
        err_set(err, err_cap, "missing trusted root pubkey");
        return 0;
    }
    if (last_err[0]) {
        err_set(err, err_cap, last_err);
    } else {
        err_set(err, err_cap, "signature verify failed");
    }
    return 0;
}
