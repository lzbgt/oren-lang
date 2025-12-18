// Minimal audit helpers for Darwin arm64 syscall number encoding.
//
// We intentionally avoid any system headers. This is for on-machine verification only.
//
// Calling convention: return value in X0.

.text
.align 2

// int64_t audit_getpid_raw(void);
.globl _audit_getpid_raw
_audit_getpid_raw:
    mov x16, #20          // getpid is syscall 20 per docs/refs/darwin_xnu_syscalls.master
    svc #0x80
    ret

// int64_t audit_getpid_encoded(void);
.globl _audit_getpid_encoded
_audit_getpid_encoded:
    mov x16, #20
    movk x16, #512, lsl #16   // +0x2000000 (x86_64-style encoding)
    svc #0x80
    ret

// uint64_t audit_thread_selfid_raw(void);
.globl _audit_thread_selfid_raw
_audit_thread_selfid_raw:
    mov x16, #372         // thread_selfid syscall 372
    svc #0x80
    ret

// uint64_t audit_thread_selfid_encoded(void);
.globl _audit_thread_selfid_encoded
_audit_thread_selfid_encoded:
    mov x16, #372
    movk x16, #512, lsl #16
    svc #0x80
    ret
