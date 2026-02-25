#include "avm_cli_util.h"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach/mach.h>
#endif

uint8_t* read_file(const char* path, size_t* len) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
    long sz = ftell(f);
    if (sz < 0) { fclose(f); return NULL; }
    *len = (size_t)sz;
    fseek(f, 0, SEEK_SET);
    uint8_t* buf = NULL;
    if (*len > 0) {
        buf = (uint8_t*)malloc(*len);
        if (!buf) { fclose(f); return NULL; }
        size_t got = fread(buf, 1, *len, f);
        if (got != *len) { free(buf); fclose(f); return NULL; }
    }
    fclose(f);
    return buf;
}

uint64_t now_ns() {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

uint64_t current_rss_bytes() {
#if defined(__APPLE__)
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count);
    if (kr != KERN_SUCCESS) return 0;
    return (uint64_t)info.resident_size;
#elif defined(__linux__)
    FILE* f = fopen("/proc/self/statm", "r");
    if (!f) return 0;
    unsigned long size_pages = 0;
    unsigned long rss_pages = 0;
    int ok = fscanf(f, "%lu %lu", &size_pages, &rss_pages);
    fclose(f);
    if (ok != 2) return 0;
    long page_size = sysconf(_SC_PAGESIZE);
    if (page_size <= 0) return 0;
    return (uint64_t)rss_pages * (uint64_t)page_size;
#else
    return 0;
#endif
}

static int is_err_map(AvmValue v) {
    if (v.type != AVM_VAL_MAP) return 0;
    AvmMap* map = v.as.m;
    if (!map) return 0;
    for (int i = 0; i < map->count; i++) {
        AvmValue k = map->keys[i];
        if (k.type == AVM_VAL_STRING && strcmp((char*)k.as.p, "__err") == 0) {
            AvmValue val = map->values[i];
            if (val.type == AVM_VAL_BOOL) return val.as.i != 0;
            if (val.type == AVM_VAL_INT) return val.as.i != 0;
            return 0;
        }
    }
    return 0;
}

void dump_error(AvmValue v) {
    if (!is_err_map(v)) return;
    AvmMap* map = v.as.m;
    int64_t code = -1;
    const char* msg = NULL;

    for (int i = 0; i < map->count; i++) {
        AvmValue k = map->keys[i];
        if (k.type != AVM_VAL_STRING) continue;
        if (strcmp((char*)k.as.p, "code") == 0 && map->values[i].type == AVM_VAL_INT) {
            code = map->values[i].as.i;
        }
        if (strcmp((char*)k.as.p, "msg") == 0 && map->values[i].type == AVM_VAL_STRING) {
            msg = (const char*)map->values[i].as.p;
        }
    }

    fprintf(stderr, "AVM error: code=%lld", (long long)code);
    if (msg) fprintf(stderr, " msg=%s", msg);
    fprintf(stderr, "\n");
}

static int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
    if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
    return -1;
}

AvmBytes* bytes_from_hex(const char* s) {
    if (!s) return NULL;
    size_t n = strlen(s);
    if ((n & 1) != 0) return NULL;
    AvmBytes* b = (AvmBytes*)malloc(sizeof(AvmBytes));
    if (!b) return NULL;
    b->len = (int)(n / 2);
    b->capacity = b->len;
    b->data = NULL;
    if (b->len > 0) {
        b->data = (uint8_t*)malloc((size_t)b->len);
        if (!b->data) { free(b); return NULL; }
    }
    for (size_t i = 0; i < n; i += 2) {
        int hi = hex_nibble(s[i]);
        int lo = hex_nibble(s[i + 1]);
        if (hi < 0 || lo < 0) { free(b->data); free(b); return NULL; }
        b->data[i / 2] = (uint8_t)((hi << 4) | lo);
    }
    return b;
}

void free_bytes_obj(AvmBytes* b) {
    if (!b) return;
    free(b->data);
    free(b);
}

static int add_trusted_pubkey_32(uint8_t out_pks[][32], size_t* out_count, size_t cap, const uint8_t* pk32) {
    if (!out_pks || !out_count || !pk32) return 0;
    if (*out_count >= cap) return 0;
    memcpy(out_pks[*out_count], pk32, 32);
    (*out_count)++;
    return 1;
}

int add_trusted_pubkey_hex_list(uint8_t out_pks[][32], size_t* out_count, size_t cap, const char* s, const char* label) {
    // Accept either:
    // - a single 64-hex pubkey
    // - a comma-separated list of 64-hex pubkeys
    if (!s || !s[0]) return 1;
    const char* p = s;
    while (*p) {
        while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' || *p == ',') p++;
        if (!*p) break;
        const char* start = p;
        while (*p && *p != ',') p++;
        size_t n = (size_t)(p - start);
        while (n > 0 && (start[n - 1] == ' ' || start[n - 1] == '\t' || start[n - 1] == '\n' || start[n - 1] == '\r')) n--;
        if (n == 0) continue;
        char tmp[256];
        if (n >= sizeof(tmp)) {
            fprintf(stderr, "Invalid %s (token too long)\n", label ? label : "trusted pubkey");
            return 0;
        }
        memcpy(tmp, start, n);
        tmp[n] = 0;
        AvmBytes* b = bytes_from_hex(tmp);
        if (!b || b->len != 32) {
            fprintf(stderr, "Invalid %s (expected 64 hex chars)\n", label ? label : "trusted pubkey");
            if (b) free_bytes_obj(b);
            return 0;
        }
        if (!add_trusted_pubkey_32(out_pks, out_count, cap, b->data)) {
            fprintf(stderr, "Too many trusted pubkeys (cap=%zu)\n", cap);
            free_bytes_obj(b);
            return 0;
        }
        free_bytes_obj(b);
    }
    return 1;
}

char* bytes_to_hex(const uint8_t* data, size_t len) {
    static const char* hexd = "0123456789abcdef";
    char* out = (char*)malloc(len * 2 + 1);
    if (!out) return NULL;
    for (size_t i = 0; i < len; i++) {
        uint8_t v = data[i];
        out[i * 2] = hexd[(v >> 4) & 0xF];
        out[i * 2 + 1] = hexd[v & 0xF];
    }
    out[len * 2] = 0;
    return out;
}

static void free_constant_value(AvmValue v) {
    if (v.type == AVM_VAL_STRING) {
        if (v.as.p) free(v.as.p);
        return;
    }
    if (v.type == AVM_VAL_BYTES) {
        AvmBytes* b = v.as.b;
        if (!b) return;
        if (b->data) free(b->data);
        free(b);
        return;
    }
    if (v.type == AVM_VAL_LIST) {
        AvmList* l = v.as.l;
        if (!l) return;
        if (l->items) free(l->items);
        free(l);
        return;
    }
    if (v.type == AVM_VAL_LIST_INT) {
        AvmListInt* l = v.as.li;
        if (!l) return;
        if (l->items) free(l->items);
        free(l);
        return;
    }
    if (v.type == AVM_VAL_MAP) {
        AvmMap* m = v.as.m;
        if (!m) return;
        if (m->keys) free(m->keys);
        if (m->values) free(m->values);
        free(m);
        return;
    }
}

void free_constant_pool(AvmValue* consts, size_t n) {
    if (!consts) return;
    for (size_t i = 0; i < n; i++) free_constant_value(consts[i]);
}

int env_truthy(const char* s) {
    if (!s || !s[0]) return 0;
    if (s[0] == '0' && !s[1]) return 0;
    return 1;
}
