#include "avm_internal.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

#if !defined(MAP_ANONYMOUS) && defined(MAP_ANON)
#define MAP_ANONYMOUS MAP_ANON
#endif

// Large RAW/BUF blocks: prefer mmap so memory can be returned to OS on free.
#define AVM_RAW_MMAP_THRESHOLD ((size_t)(1u << 20)) // 1 MiB

typedef struct AvmAllocHdr {
    uint64_t magic;
    AvmVM* owner;
    uint64_t size;
    uint64_t charged_size;
    uint32_t alloc_id;   // 0 if untracked/unowned
    uint32_t alloc_pc;   // best-effort VM pc at allocation time (rolling)
    uint8_t alloc_kind;  // best-effort classification (rolling)
    uint8_t alloc_backend; // 0=malloc, 1=mmap (rolling)
    uint8_t alloc_flags; // rolling flags (see AVM_ALLOC_FLAG_*)
    // Pad so `sizeof(AvmAllocHdr)` is 64 bytes.
    // This enables 64-byte-aligned user pointers for BUF allocations when using posix_memalign.
    uint8_t _pad0[5];
    struct AvmAllocHdr* prev;
    struct AvmAllocHdr* next;
} AvmAllocHdr;

static const uint64_t AVM_ALLOC_MAGIC = 0x41564d414c4c4f43ull; // "AVMALLOC"
static const uint8_t AVM_ALLOC_FLAG_FREELIST = 1u << 0;

static AvmVM* g_alloc_owner = NULL;
static int g_alloc_unbudgeted = 0;
static int g_last_alloc_err = 0; // 0=none, else AVM_ERR_* (budget/internal)

void avm_alloc_owner_push(AvmVM* vm, AvmVM** prev) {
    if (prev) *prev = g_alloc_owner;
    g_alloc_owner = vm;
}

void avm_alloc_owner_pop(AvmVM* prev) {
    g_alloc_owner = prev;
}

void avm_alloc_unbudgeted_push(int* prev) {
    if (prev) *prev = g_alloc_unbudgeted;
    g_alloc_unbudgeted = 1;
}

void avm_alloc_unbudgeted_pop(int prev) {
    g_alloc_unbudgeted = prev;
}

static AvmAllocHdr* avm_alloc_hdr_from_ptr(void* p) {
    if (!p) return NULL;
    AvmAllocHdr* h = ((AvmAllocHdr*)p) - 1;
    if (h->magic != AVM_ALLOC_MAGIC) return NULL;
    return h;
}

static unsigned avm_freelist_bucket_index(size_t size) {
    if (size <= 1) return 0;
    unsigned idx = 0;
    size_t v = size;
    while (v > 1 && idx < (unsigned)(AVM_FREELIST_BUCKETS - 1)) {
        v >>= 1;
        idx++;
    }
    return idx;
}

static int avm_tmp_freelist_enabled(AvmVM* owner, size_t size) {
    if (!owner || owner->tmp_freelist_enabled == 0) return 0;
    if (owner->tmp_freelist_cap_bytes == 0) return 0;
    if (owner->tmp_freelist_max_block_bytes > 0 && size > owner->tmp_freelist_max_block_bytes) return 0;
    return 1;
}

static AvmAllocHdr* avm_tmp_freelist_take(AvmVM* owner, size_t size) {
    if (!owner) return NULL;
    unsigned idx = avm_freelist_bucket_index(size);
    if (!owner->tmp_freelist_buckets[idx]) {
        owner->tmp_freelist_misses++;
        return NULL;
    }
    AvmAllocHdr* prev = NULL;
    AvmAllocHdr* cur = (AvmAllocHdr*)owner->tmp_freelist_buckets[idx];
    while (cur) {
        if (cur->size == size) {
            if (prev) prev->next = cur->next;
            else owner->tmp_freelist_buckets[idx] = cur->next;
            cur->next = NULL;
            cur->prev = NULL;
            if (owner->tmp_freelist_bytes >= cur->size) owner->tmp_freelist_bytes -= cur->size;
            else owner->tmp_freelist_bytes = 0;
            owner->tmp_freelist_hits++;
            return cur;
        }
        prev = cur;
        cur = cur->next;
    }
    owner->tmp_freelist_misses++;
    return NULL;
}

static int avm_tmp_freelist_push(AvmVM* owner, AvmAllocHdr* h) {
    if (!owner || !h) return 0;
    if (!avm_tmp_freelist_enabled(owner, (size_t)h->size)) return 0;
    if (owner->tmp_freelist_bytes + h->size > owner->tmp_freelist_cap_bytes) {
        owner->tmp_freelist_evictions++;
        return 0;
    }
    unsigned idx = avm_freelist_bucket_index((size_t)h->size);
    h->alloc_flags |= AVM_ALLOC_FLAG_FREELIST;
    h->prev = NULL;
    h->next = (AvmAllocHdr*)owner->tmp_freelist_buckets[idx];
    owner->tmp_freelist_buckets[idx] = h;
    owner->tmp_freelist_bytes += h->size;
    return 1;
}

static int avm_list_freelist_enabled(AvmVM* owner, size_t size) {
    if (!owner || owner->list_freelist_enabled == 0) return 0;
    if (owner->list_freelist_cap_bytes == 0) return 0;
    if (owner->list_freelist_max_block_bytes > 0 && size > owner->list_freelist_max_block_bytes) return 0;
    return 1;
}

static AvmAllocHdr* avm_list_freelist_take(AvmVM* owner, size_t size) {
    if (!owner) return NULL;
    unsigned idx = avm_freelist_bucket_index(size);
    if (!owner->list_freelist_buckets[idx]) {
        owner->list_freelist_misses++;
        return NULL;
    }
    AvmAllocHdr* prev = NULL;
    AvmAllocHdr* cur = (AvmAllocHdr*)owner->list_freelist_buckets[idx];
    while (cur) {
        if (cur->size == size) {
            if (prev) prev->next = cur->next;
            else owner->list_freelist_buckets[idx] = cur->next;
            cur->next = NULL;
            cur->prev = NULL;
            if (owner->list_freelist_bytes >= cur->size) owner->list_freelist_bytes -= cur->size;
            else owner->list_freelist_bytes = 0;
            owner->list_freelist_hits++;
            return cur;
        }
        prev = cur;
        cur = cur->next;
    }
    owner->list_freelist_misses++;
    return NULL;
}

static int avm_list_freelist_push(AvmVM* owner, AvmAllocHdr* h) {
    if (!owner || !h) return 0;
    if (!avm_list_freelist_enabled(owner, (size_t)h->size)) return 0;
    if (owner->list_freelist_bytes + h->size > owner->list_freelist_cap_bytes) {
        owner->list_freelist_evictions++;
        return 0;
    }
    unsigned idx = avm_freelist_bucket_index((size_t)h->size);
    h->alloc_flags |= AVM_ALLOC_FLAG_FREELIST;
    h->prev = NULL;
    h->next = (AvmAllocHdr*)owner->list_freelist_buckets[idx];
    owner->list_freelist_buckets[idx] = h;
    owner->list_freelist_bytes += h->size;
    return 1;
}

void* avm_heap_malloc_k(size_t size, uint8_t kind) {
    g_last_alloc_err = 0;
    AvmVM* owner = g_alloc_owner;
    if (!g_alloc_unbudgeted && owner && owner->heap_budget_bytes > 0) {
        if (size > owner->heap_budget_bytes) {
            g_last_alloc_err = AVM_ERR_BUDGET;
            return NULL;
        }
        if (owner->heap_used_bytes + size > owner->heap_budget_bytes) {
            g_last_alloc_err = AVM_ERR_BUDGET;
            return NULL;
        }
    }

    if (kind == AVM_ALLOC_KIND_TMP && avm_tmp_freelist_enabled(owner, size)) {
        AvmAllocHdr* fh = avm_tmp_freelist_take(owner, size);
        if (fh) {
            fh->owner = owner;
            fh->charged_size = (!g_alloc_unbudgeted && owner) ? size : 0;
            fh->alloc_id = owner ? owner->alloc_next_id++ : 0;
            fh->alloc_pc = owner ? (uint32_t)owner->pc : 0;
            fh->alloc_kind = kind;
            fh->alloc_flags &= (uint8_t)(~AVM_ALLOC_FLAG_FREELIST);
            fh->prev = NULL;
            fh->next = NULL;
            if (owner) {
                fh->next = (AvmAllocHdr*)owner->heap_allocs_head;
                if (fh->next) fh->next->prev = fh;
                owner->heap_allocs_head = fh;
            }
            if (fh->charged_size && owner) owner->heap_used_bytes += fh->charged_size;
            if (owner && owner->trace_bytes_enabled && fh->charged_size > 0) {
                uint32_t pc = (uint32_t)owner->pc;
                (void)trace_emit_alloc_bytes(owner, pc, fh->alloc_id, fh->alloc_kind, (uint32_t)fh->size, (uint32_t)fh->charged_size);
            }
            return (void*)(fh + 1);
        }
    }
    if ((kind == AVM_ALLOC_KIND_LIST || kind == AVM_ALLOC_KIND_LIST_INT) &&
        avm_list_freelist_enabled(owner, size)) {
        AvmAllocHdr* fh = avm_list_freelist_take(owner, size);
        if (fh) {
            fh->owner = owner;
            fh->charged_size = (!g_alloc_unbudgeted && owner) ? size : 0;
            fh->alloc_id = owner ? owner->alloc_next_id++ : 0;
            fh->alloc_pc = owner ? (uint32_t)owner->pc : 0;
            fh->alloc_kind = kind;
            fh->alloc_flags &= (uint8_t)(~AVM_ALLOC_FLAG_FREELIST);
            fh->prev = NULL;
            fh->next = NULL;
            if (owner) {
                fh->next = (AvmAllocHdr*)owner->heap_allocs_head;
                if (fh->next) fh->next->prev = fh;
                owner->heap_allocs_head = fh;
            }
            if (fh->charged_size && owner) owner->heap_used_bytes += fh->charged_size;
            if (owner && owner->trace_bytes_enabled && fh->charged_size > 0) {
                uint32_t pc = (uint32_t)owner->pc;
                (void)trace_emit_alloc_bytes(owner, pc, fh->alloc_id, fh->alloc_kind, (uint32_t)fh->size, (uint32_t)fh->charged_size);
            }
            return (void*)(fh + 1);
        }
    }

    size_t total = sizeof(AvmAllocHdr) + size;
    AvmAllocHdr* h = NULL;
    // Typed buffers are hot in HPC-style workloads; align to cache line for NEON-friendly kernels.
    // We keep this deterministic and portable by using `posix_memalign` (free-able with `free`).
    if (kind == AVM_ALLOC_KIND_BUF || kind == AVM_ALLOC_KIND_RAW) {
        if (size >= AVM_RAW_MMAP_THRESHOLD) {
            void* base = mmap(NULL, total, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if (base == MAP_FAILED) {
                g_last_alloc_err = AVM_ERR_INTERNAL;
                return NULL;
            }
            h = (AvmAllocHdr*)base;
            h->alloc_backend = 1;
        } else {
            void* p = NULL;
            int er = posix_memalign(&p, 64u, total);
            if (er != 0 || !p) {
                g_last_alloc_err = AVM_ERR_INTERNAL;
                return NULL;
            }
            h = (AvmAllocHdr*)p;
            h->alloc_backend = 0;
        }
    } else {
        h = (AvmAllocHdr*)malloc(total);
        if (!h) {
            g_last_alloc_err = AVM_ERR_INTERNAL;
            return NULL;
        }
        h->alloc_backend = 0;
    }
    h->magic = AVM_ALLOC_MAGIC;
    h->owner = owner;
    h->size = size;
    h->charged_size = (!g_alloc_unbudgeted && owner) ? size : 0;
    h->alloc_id = 0;
    h->alloc_pc = owner ? (uint32_t)owner->pc : 0;
    h->alloc_kind = kind;
    h->alloc_flags = 0;
    // alloc_backend is already set in the allocation path above.
    h->prev = NULL;
    h->next = NULL;
    if (owner) {
        h->alloc_id = owner->alloc_next_id++;
        h->next = (AvmAllocHdr*)owner->heap_allocs_head;
        if (h->next) h->next->prev = h;
        owner->heap_allocs_head = h;
    }
    if (h->charged_size && owner) owner->heap_used_bytes += h->charged_size;

    // Best-effort diagnostics: allocation events go to trace BYTES only (not TRACE_HASH).
    // Skip unbudgeted allocations to avoid recursion (trace bytes storage is unbudgeted).
    if (owner && owner->trace_bytes_enabled && h->charged_size > 0) {
        uint32_t pc = (uint32_t)owner->pc;
        (void)trace_emit_alloc_bytes(owner, pc, h->alloc_id, h->alloc_kind, (uint32_t)h->size, (uint32_t)h->charged_size);
    }

    return (void*)(h + 1);
}

void avm_heap_free(void* p) {
    if (!p) return;
    AvmAllocHdr* h = avm_alloc_hdr_from_ptr(p);
    if (!h) {
        free(p);
        return;
    }
    if (h->alloc_flags & AVM_ALLOC_FLAG_FREELIST) return;

    // Best-effort diagnostics: free events go to trace BYTES only (not TRACE_HASH).
    // Skip unbudgeted allocations (charged_size==0) to avoid recursion & noise.
    if (h->owner && h->owner->trace_bytes_enabled && h->charged_size > 0) {
        uint32_t pc = (uint32_t)h->owner->pc;
        (void)trace_emit_free_bytes(h->owner, pc, h->alloc_id, h->alloc_kind, (uint32_t)h->size, (uint32_t)h->charged_size);
    }

    if (h->owner) {
        // Remove from owner allocation list (if still linked).
        if (h->prev) h->prev->next = h->next;
        else if ((AvmAllocHdr*)h->owner->heap_allocs_head == h) h->owner->heap_allocs_head = h->next;
        if (h->next) h->next->prev = h->prev;
        h->prev = NULL;
        h->next = NULL;

        if (h->charged_size && h->owner->heap_used_bytes >= h->charged_size) h->owner->heap_used_bytes -= h->charged_size;
        else if (h->charged_size) h->owner->heap_used_bytes = 0;
    }
    if (h->owner && h->alloc_kind == AVM_ALLOC_KIND_TMP && avm_tmp_freelist_push(h->owner, h)) {
        return;
    }
    if (h->owner && (h->alloc_kind == AVM_ALLOC_KIND_LIST || h->alloc_kind == AVM_ALLOC_KIND_LIST_INT) &&
        avm_list_freelist_push(h->owner, h)) {
        return;
    }
    h->magic = 0;
    if (h->alloc_backend == 1) {
        size_t total = sizeof(AvmAllocHdr) + (size_t)h->size;
        (void)munmap((void*)h, total);
    } else {
        free(h);
    }
}

int avm_heap_is_owned_by(AvmVM* vm, void* p) {
    if (!vm || !p) return 0;
    for (AvmAllocHdr* h = (AvmAllocHdr*)vm->heap_allocs_head; h; h = h->next) {
        if ((void*)(h + 1) == p) return 1;
    }
    return 0;
}

void* avm_heap_realloc_k(void* p, size_t new_size, uint8_t kind) {
    g_last_alloc_err = 0;
    if (!p) return avm_heap_malloc_k(new_size, kind);

    AvmAllocHdr* h = avm_alloc_hdr_from_ptr(p);
    if (!h) {
        // Unknown pointer: fallback to libc realloc (unbudgeted).
        void* np = realloc(p, new_size);
        if (!np) g_last_alloc_err = AVM_ERR_INTERNAL;
        return np;
    }

    AvmVM* owner = h->owner;
    uint64_t old_size = h->size;

    // Preserve BUF alignment guarantees: use alloc+copy instead of libc realloc.
    if (kind == AVM_ALLOC_KIND_BUF || kind == AVM_ALLOC_KIND_RAW ||
        kind == AVM_ALLOC_KIND_LIST || kind == AVM_ALLOC_KIND_LIST_INT) {
        void* np = avm_heap_malloc_k(new_size, kind);
        if (!np) return NULL;
        size_t copy_n = (old_size < (uint64_t)new_size) ? (size_t)old_size : new_size;
        if (copy_n) memcpy(np, p, copy_n);
        avm_heap_free(p);
        return np;
    }
    uint64_t old_charged = h->charged_size;
    uint64_t new_charged = (old_charged != 0) ? (uint64_t)new_size : 0;

    uint64_t used_without_old = 0;
    if (owner) {
        used_without_old = owner->heap_used_bytes;
        if (used_without_old >= old_charged) used_without_old -= old_charged;
        else used_without_old = 0;
    }

    if (!g_alloc_unbudgeted && owner && owner->heap_budget_bytes > 0 && new_charged != 0) {
        if (new_charged > owner->heap_budget_bytes) {
            g_last_alloc_err = AVM_ERR_BUDGET;
            return NULL;
        }
        if (used_without_old + new_charged > owner->heap_budget_bytes) {
            g_last_alloc_err = AVM_ERR_BUDGET;
            return NULL;
        }
    }

    size_t total = sizeof(AvmAllocHdr) + new_size;
    AvmAllocHdr* nh = (AvmAllocHdr*)malloc(total);
    if (!nh) {
        g_last_alloc_err = AVM_ERR_INTERNAL;
        return NULL;
    }
    nh->magic = AVM_ALLOC_MAGIC;
    nh->owner = owner;
    nh->size = new_size;
    nh->charged_size = new_charged;
    nh->alloc_id = h->alloc_id;
    nh->alloc_pc = owner ? (uint32_t)owner->pc : 0;
    nh->alloc_kind = kind ? kind : h->alloc_kind;
    nh->alloc_backend = 0;
    nh->alloc_flags = 0;
    nh->prev = NULL;
    nh->next = NULL;

    size_t copy_n = (old_size < new_size) ? (size_t)old_size : new_size;
    if (copy_n > 0) memcpy(nh + 1, h + 1, copy_n);

    if (owner) {
        // Link new header into owner list.
        nh->next = (AvmAllocHdr*)owner->heap_allocs_head;
        if (nh->next) nh->next->prev = nh;
        owner->heap_allocs_head = nh;
        // Update accounting in one step (old already subtracted).
        owner->heap_used_bytes = used_without_old + new_charged;
    }

    // Unlink and free old header without adjusting accounting again (already handled above).
    if (owner) {
        if (h->prev) h->prev->next = h->next;
        else if ((AvmAllocHdr*)owner->heap_allocs_head == h) owner->heap_allocs_head = h->next;
        if (h->next) h->next->prev = h->prev;
    }
    h->magic = 0;
    free(h);

    // Best-effort diagnostics: realloc events go to trace BYTES only (not TRACE_HASH).
    // Only log budgeted allocations (charged_size>0) to avoid recursion/noise.
    if (owner && owner->trace_bytes_enabled && new_charged > 0) {
        (void)trace_emit_realloc_bytes(owner, (uint32_t)owner->pc, nh->alloc_id, nh->alloc_kind,
            (uint32_t)old_size, (uint32_t)new_size, (uint32_t)old_charged, (uint32_t)new_charged);
    }

    return (void*)(nh + 1);
}

AvmValue avm_alloc_fail_value(void) {
    if (g_last_alloc_err == AVM_ERR_BUDGET) return avm_err(AVM_ERR_BUDGET, "budget exceeded (mem)");
    return avm_err(AVM_ERR_INTERNAL, "oom");
}

void avm_release_unreachable_allocs(AvmVM* vm) {
    if (!vm) return;
    AvmAllocHdr* h = (AvmAllocHdr*)vm->heap_allocs_head;
    while (h) {
        AvmAllocHdr* next = h->next;
        if (h->charged_size && vm->heap_used_bytes >= h->charged_size) vm->heap_used_bytes -= h->charged_size;
        else if (h->charged_size) vm->heap_used_bytes = 0;
        h->magic = 0;
        if (h->alloc_backend == 1) {
            size_t total = sizeof(AvmAllocHdr) + (size_t)h->size;
            (void)munmap((void*)h, total);
        } else {
            free(h);
        }
        h = next;
    }
    vm->heap_allocs_head = NULL;
    vm->heap_used_bytes = 0;
}

void avm_release_tmp_freelist(AvmVM* vm) {
    if (!vm) return;
    for (int bi = 0; bi < AVM_FREELIST_BUCKETS; bi++) {
        AvmAllocHdr* h = (AvmAllocHdr*)vm->tmp_freelist_buckets[bi];
        while (h) {
            AvmAllocHdr* next = h->next;
            h->magic = 0;
            if (h->alloc_backend == 1) {
                size_t total = sizeof(AvmAllocHdr) + (size_t)h->size;
                (void)munmap((void*)h, total);
            } else {
                free(h);
            }
            h = next;
        }
        vm->tmp_freelist_buckets[bi] = NULL;
    }
    vm->tmp_freelist_bytes = 0;
}

void avm_release_list_freelist(AvmVM* vm) {
    if (!vm) return;
    for (int bi = 0; bi < AVM_FREELIST_BUCKETS; bi++) {
        AvmAllocHdr* h = (AvmAllocHdr*)vm->list_freelist_buckets[bi];
        while (h) {
            AvmAllocHdr* next = h->next;
            h->magic = 0;
            if (h->alloc_backend == 1) {
                size_t total = sizeof(AvmAllocHdr) + (size_t)h->size;
                (void)munmap((void*)h, total);
            } else {
                free(h);
            }
            h = next;
        }
        vm->list_freelist_buckets[bi] = NULL;
    }
    vm->list_freelist_bytes = 0;
}
