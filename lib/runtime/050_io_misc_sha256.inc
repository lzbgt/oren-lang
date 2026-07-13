typedef struct {
    uint8_t data[64];
    uint32_t datalen;
    uint64_t bitlen;
    uint32_t state[8];
} OrenSha256Ctx;

static uint32_t oren_sha256_rotr(uint32_t x, uint32_t n) { return (x >> n) | (x << (32 - n)); }
static uint32_t oren_sha256_ch(uint32_t x, uint32_t y, uint32_t z) { return (x & y) ^ (~x & z); }
static uint32_t oren_sha256_maj(uint32_t x, uint32_t y, uint32_t z) { return (x & y) ^ (x & z) ^ (y & z); }
static uint32_t oren_sha256_ep0(uint32_t x) { return oren_sha256_rotr(x, 2) ^ oren_sha256_rotr(x, 13) ^ oren_sha256_rotr(x, 22); }
static uint32_t oren_sha256_ep1(uint32_t x) { return oren_sha256_rotr(x, 6) ^ oren_sha256_rotr(x, 11) ^ oren_sha256_rotr(x, 25); }
static uint32_t oren_sha256_sig0(uint32_t x) { return oren_sha256_rotr(x, 7) ^ oren_sha256_rotr(x, 18) ^ (x >> 3); }
static uint32_t oren_sha256_sig1(uint32_t x) { return oren_sha256_rotr(x, 17) ^ oren_sha256_rotr(x, 19) ^ (x >> 10); }

static const uint32_t OREN_SHA256_K[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

static void oren_sha256_transform(OrenSha256Ctx* ctx, const uint8_t data[64]) {
    uint32_t m[64];
    for (int i = 0; i < 16; i++) {
        int j = i * 4;
        m[i] = ((uint32_t)data[j] << 24) | ((uint32_t)data[j + 1] << 16) | ((uint32_t)data[j + 2] << 8) | (uint32_t)data[j + 3];
    }
    for (int i = 16; i < 64; i++) {
        m[i] = oren_sha256_sig1(m[i - 2]) + m[i - 7] + oren_sha256_sig0(m[i - 15]) + m[i - 16];
    }

    uint32_t a = ctx->state[0];
    uint32_t b = ctx->state[1];
    uint32_t c = ctx->state[2];
    uint32_t d = ctx->state[3];
    uint32_t e = ctx->state[4];
    uint32_t f = ctx->state[5];
    uint32_t g = ctx->state[6];
    uint32_t h = ctx->state[7];

    for (int i = 0; i < 64; i++) {
        uint32_t t1 = h + oren_sha256_ep1(e) + oren_sha256_ch(e, f, g) + OREN_SHA256_K[i] + m[i];
        uint32_t t2 = oren_sha256_ep0(a) + oren_sha256_maj(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }

    ctx->state[0] += a;
    ctx->state[1] += b;
    ctx->state[2] += c;
    ctx->state[3] += d;
    ctx->state[4] += e;
    ctx->state[5] += f;
    ctx->state[6] += g;
    ctx->state[7] += h;
}

static void oren_sha256_init(OrenSha256Ctx* ctx) {
    ctx->datalen = 0;
    ctx->bitlen = 0;
    ctx->state[0] = 0x6a09e667;
    ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372;
    ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f;
    ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab;
    ctx->state[7] = 0x5be0cd19;
}

static void oren_sha256_update(OrenSha256Ctx* ctx, const uint8_t* data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        ctx->data[ctx->datalen] = data[i];
        ctx->datalen++;
        if (ctx->datalen == 64) {
            oren_sha256_transform(ctx, ctx->data);
            ctx->bitlen += 512;
            ctx->datalen = 0;
        }
    }
}

static void oren_sha256_final(OrenSha256Ctx* ctx, uint8_t out[32]) {
    uint32_t i = ctx->datalen;

    // Pad with a single 1 bit then zeros.
    if (ctx->datalen < 56) {
        ctx->data[i++] = 0x80;
        while (i < 56) ctx->data[i++] = 0x00;
    } else {
        ctx->data[i++] = 0x80;
        while (i < 64) ctx->data[i++] = 0x00;
        oren_sha256_transform(ctx, ctx->data);
        memset(ctx->data, 0, 56);
    }

    ctx->bitlen += (uint64_t)ctx->datalen * 8;
    ctx->data[63] = (uint8_t)(ctx->bitlen);
    ctx->data[62] = (uint8_t)(ctx->bitlen >> 8);
    ctx->data[61] = (uint8_t)(ctx->bitlen >> 16);
    ctx->data[60] = (uint8_t)(ctx->bitlen >> 24);
    ctx->data[59] = (uint8_t)(ctx->bitlen >> 32);
    ctx->data[58] = (uint8_t)(ctx->bitlen >> 40);
    ctx->data[57] = (uint8_t)(ctx->bitlen >> 48);
    ctx->data[56] = (uint8_t)(ctx->bitlen >> 56);
    oren_sha256_transform(ctx, ctx->data);

    for (i = 0; i < 4; i++) {
        out[i]      = (uint8_t)((ctx->state[0] >> (24 - i * 8)) & 0xff);
        out[i + 4]  = (uint8_t)((ctx->state[1] >> (24 - i * 8)) & 0xff);
        out[i + 8]  = (uint8_t)((ctx->state[2] >> (24 - i * 8)) & 0xff);
        out[i + 12] = (uint8_t)((ctx->state[3] >> (24 - i * 8)) & 0xff);
        out[i + 16] = (uint8_t)((ctx->state[4] >> (24 - i * 8)) & 0xff);
        out[i + 20] = (uint8_t)((ctx->state[5] >> (24 - i * 8)) & 0xff);
        out[i + 24] = (uint8_t)((ctx->state[6] >> (24 - i * 8)) & 0xff);
        out[i + 28] = (uint8_t)((ctx->state[7] >> (24 - i * 8)) & 0xff);
    }
}

OrenValue oren_sha256_range(OrenValue bytes, OrenValue start, OrenValue length) {
    if (start.type != OREN_TYPE_INT || length.type != OREN_TYPE_INT) {
        oren_panic("sha256_range expects (list<int>|u8_buf, int, int)");
        return OREN_NIL; // Should not be reached
    }
    long long s = start.as.int_val;
    long long n = length.as.int_val;

    const char* err_msg = NULL;
    size_t total = 0;
    if (!runtime_bytes_len_checked(bytes, &total, &err_msg)) {
        oren_panic(err_msg ? err_msg : "sha256_range expects (list<int>|u8_buf, int, int)");
        return OREN_NIL;
    }
    if (s < 0 || n < 0 || (uint64_t)s > (uint64_t)SIZE_MAX || (uint64_t)n > (uint64_t)SIZE_MAX ||
        !runtime_bytes_range_ok_size(total, (size_t)s, (size_t)n)) {
        char buf[256];
        snprintf(buf, sizeof(buf), "sha256_range out of bounds (s=%lld, n=%lld, count=%llu)", s, n, (unsigned long long)total);
        oren_panic(buf);
        return OREN_NIL; // Should not be reached
    }

    OrenSha256Ctx ctx;
    oren_sha256_init(&ctx);

    uint8_t chunk[64 * 1024];
    size_t off = 0;
    while (off < (size_t)n) {
        size_t want = (size_t)n - off;
        if (want > sizeof(chunk)) {
            want = sizeof(chunk);
        }
        if (!runtime_bytes_copy_span(bytes, (size_t)s + off, want, chunk, &err_msg)) {
            oren_panic(err_msg ? err_msg : "sha256_range expects list<int>|u8_buf bytes");
            return OREN_NIL;
        }
        oren_sha256_update(&ctx, chunk, want);
        off += want;
    }

    uint8_t digest[32];
    oren_sha256_final(&ctx, digest);

    lock_collections();
    OrenList* out = malloc(sizeof(OrenList));
    if (!out) {
        unlock_collections();
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("sha256_range: alloc failed"));
    }
    oren_register_alloc(out, OREN_ALLOC_LIST);

    out->count = 32;
    out->capacity = 32;
    out->all_int = 1;
    out->items = malloc(sizeof(OrenValue) * 32);
    if (!out->items) {
        unlock_collections();
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("sha256_range: alloc failed"));
    }
    for (int i = 0; i < 32; i++) {
        out->items[i] = oren_int(digest[i]);
    }
    unlock_collections();
    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = out;
    return v;
}

OrenValue oren_sha256_string(OrenValue s) {
    if (s.type != OREN_TYPE_STRING) {
        oren_panic("sha256_string expects string");
        return OREN_NIL; // Should not be reached
    }
    const unsigned char* p = (const unsigned char*)s.as.string_val;
    size_t n = strlen((const char*)p);

    OrenSha256Ctx ctx;
    oren_sha256_init(&ctx);
    if (n > 0) {
        oren_sha256_update(&ctx, p, n);
    }

    uint8_t digest[32];
    oren_sha256_final(&ctx, digest);

    lock_collections();
    OrenList* out = malloc(sizeof(OrenList));
    if (!out) {
        unlock_collections();
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("sha256_string: alloc failed"));
    }
    oren_register_alloc(out, OREN_ALLOC_LIST);

    out->count = 32;
    out->capacity = 32;
    out->all_int = 1;
    out->items = malloc(sizeof(OrenValue) * 32);
    if (!out->items) {
        unlock_collections();
        return oren_err(oren_int(OREN_ERR_INTERNAL), oren_string("sha256_string: alloc failed"));
    }
    for (int i = 0; i < 32; i++) {
        out->items[i] = oren_int(digest[i]);
    }
    unlock_collections();

    OrenValue v;
    v.type = OREN_TYPE_LIST;
    v.as.list_val = out;
    return v;
}
