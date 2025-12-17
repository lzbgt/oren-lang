#include "avm_internal.h"

#include <stdlib.h>
#include <string.h>

typedef struct AvmAllocHdr {
    uint64_t magic;
    AvmVM* owner;
    uint64_t size;
    uint64_t charged_size;
    uint32_t alloc_id;   // 0 if untracked/unowned
    uint32_t alloc_pc;   // best-effort VM pc at allocation time (rolling)
    uint8_t alloc_kind;  // best-effort classification (rolling)
    uint8_t _pad0[7];
    struct AvmAllocHdr* prev;
    struct AvmAllocHdr* next;
} AvmAllocHdr;

static const uint64_t AVM_ALLOC_MAGIC = 0x41564d414c4c4f43ull; // "AVMALLOC"

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

    size_t total = sizeof(AvmAllocHdr) + size;
    AvmAllocHdr* h = (AvmAllocHdr*)malloc(total);
    if (!h) {
        g_last_alloc_err = AVM_ERR_INTERNAL;
        return NULL;
    }
    h->magic = AVM_ALLOC_MAGIC;
    h->owner = owner;
    h->size = size;
    h->charged_size = (!g_alloc_unbudgeted && owner) ? size : 0;
    h->alloc_id = 0;
    h->alloc_pc = owner ? (uint32_t)owner->pc : 0;
    h->alloc_kind = kind;
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
    h->magic = 0;
    free(h);
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
        free(h);
        h = next;
    }
    vm->heap_allocs_head = NULL;
    vm->heap_used_bytes = 0;
}

