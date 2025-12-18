#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

int64_t audit_getpid_raw(void);
int64_t audit_getpid_encoded(void);
uint64_t audit_thread_selfid_raw(void);
uint64_t audit_thread_selfid_encoded(void);

int main(void) {
    pid_t libc_pid = getpid();
    int64_t raw_pid = audit_getpid_raw();
    int64_t enc_pid = audit_getpid_encoded();

    uint64_t raw_tid = audit_thread_selfid_raw();
    uint64_t enc_tid = audit_thread_selfid_encoded();

    printf("libc getpid: %lld\n", (long long)libc_pid);
    printf("svc raw getpid (x16=20): %lld\n", (long long)raw_pid);
    printf("svc encoded getpid (x16=0x2000000|20): %lld\n", (long long)enc_pid);

    printf("svc raw thread_selfid (x16=372): %llu\n", (unsigned long long)raw_tid);
    printf("svc encoded thread_selfid (x16=0x2000000|372): %llu\n", (unsigned long long)enc_tid);

    // Exit code:
    // - 0: raw matches libc and encoded differs (expected)
    // - 1: raw mismatch
    // - 2: encoded unexpectedly matches
    if (raw_pid != (int64_t)libc_pid) {
        return 1;
    }
    if (enc_pid == (int64_t)libc_pid) {
        return 2;
    }
    return 0;
}
