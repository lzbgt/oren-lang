#include "avm_cli_fs.h"
#include <stdlib.h>
#include <string.h>

void parse_fs_allow_prefixes(AvmVM* vm, const char* s) {
    if (!vm) return;
    if (!s || !s[0]) return; // empty => allow all

    // First pass: count commas + 1
    int count = 1;
    for (const char* p = s; *p; p++) {
        if (*p == ',') count++;
    }

    vm->fs_allow_prefixes = (char**)calloc((size_t)count, sizeof(char*));
    vm->fs_allow_prefix_count = 0;

    const char* cur = s;
    while (*cur) {
        while (*cur == ' ') cur++;
        const char* start = cur;
        while (*cur && *cur != ',') cur++;
        const char* end = cur;
        while (end > start && end[-1] == ' ') end--;

        size_t len = (size_t)(end - start);
        if (len > 0) {
            char* pref = (char*)malloc(len + 1);
            memcpy(pref, start, len);
            pref[len] = 0;
            vm->fs_allow_prefixes[vm->fs_allow_prefix_count++] = pref;
        }

        if (*cur == ',') cur++;
    }
}

static void free_fs_mounts(char*** virt, char*** host, int* count) {
    if (virt && *virt) {
        for (int i = 0; count && i < *count; i++) {
            if ((*virt)[i]) free((*virt)[i]);
        }
        free(*virt);
        *virt = NULL;
    }
    if (host && *host) {
        for (int i = 0; count && i < *count; i++) {
            if ((*host)[i]) free((*host)[i]);
        }
        free(*host);
        *host = NULL;
    }
    if (count) *count = 0;
}

void parse_fs_mounts(char*** out_virt, char*** out_host, int* out_count, const char* s) {
    if (!out_virt || !out_host || !out_count) return;
    free_fs_mounts(out_virt, out_host, out_count);
    if (!s || !s[0]) return; // empty => no mounts configured

    // Count candidate tokens (CSV)
    int count = 0;
    for (const char* p = s; *p; p++) {
        if (*p == ',') count++;
    }
    count++; // commas + 1

    char** v = (char**)calloc((size_t)count, sizeof(char*));
    char** h = (char**)calloc((size_t)count, sizeof(char*));
    if (!v || !h) { if (v) free(v); if (h) free(h); return; }

    int n = 0;
    const char* cur = s;
    while (*cur) {
        while (*cur == ' ') cur++;
        const char* start = cur;
        while (*cur && *cur != ',') cur++;
        const char* end = cur;
        while (end > start && end[-1] == ' ') end--;

        // Split on first '='
        const char* eq = NULL;
        for (const char* p = start; p < end; p++) {
            if (*p == '=') { eq = p; break; }
        }
        if (eq && eq > start && (eq + 1) < end) {
            const char* vs = start;
            const char* ve = eq;
            const char* hs = eq + 1;
            const char* he = end;
            while (ve > vs && ve[-1] == ' ') ve--;
            while (hs < he && *hs == ' ') hs++;
            while (he > hs && he[-1] == ' ') he--;

            size_t vl = (size_t)(ve - vs);
            size_t hl = (size_t)(he - hs);
            if (vl > 0 && hl > 0) {
                v[n] = (char*)malloc(vl + 1);
                h[n] = (char*)malloc(hl + 1);
                if (!v[n] || !h[n]) {
                    if (v[n]) free(v[n]);
                    if (h[n]) free(h[n]);
                } else {
                    memcpy(v[n], vs, vl); v[n][vl] = 0;
                    memcpy(h[n], hs, hl); h[n][hl] = 0;
                    n++;
                }
            }
        }

        if (*cur == ',') cur++;
    }

    *out_virt = v;
    *out_host = h;
    *out_count = n;
}

int parse_fs_backend_kind(const char* s, int* out_kind) {
    if (!out_kind) return 0;
    *out_kind = 0;
    if (!s || !s[0]) return 1;
    if (strcmp(s, "host") == 0) { *out_kind = 0; return 1; }
    if (strcmp(s, "vfs") == 0) { *out_kind = 1; return 1; }
    return 0;
}

int parse_proc_backend_kind(const char* s, int* out_kind) {
    if (!out_kind) return 0;
    *out_kind = 0;
    if (!s || !s[0]) return 1;
    if (strcmp(s, "host") == 0) { *out_kind = 0; return 1; }
    if (strcmp(s, "vproc") == 0) { *out_kind = 1; return 1; }
    return 0;
}

int parse_net_backend_kind(const char* s, int* out_kind) {
    if (!out_kind) return 0;
    *out_kind = 0;
    if (!s || !s[0]) return 1;
    if (strcmp(s, "host") == 0) { *out_kind = 0; return 1; }
    if (strcmp(s, "vnet") == 0) { *out_kind = 1; return 1; }
    return 0;
}
