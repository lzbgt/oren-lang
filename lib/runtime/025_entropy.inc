// --- Entropy / randomness (C backend runtime; host-effectful) ---
//
// This runtime is used by the stage0 bootstrap (Go -> C backend) and is allowed to use libc/Win32.
//
// Contract:
//   oren_getentropy(ptr:int, len:int) -> 0 on success, or -errno on failure.
//
// Notes:
// - On POSIX we use `/dev/urandom` to avoid relying on specific libc versions for `getrandom(2)`.
// - On Windows we use bcrypt!BCryptGenRandom via LoadLibrary/GetProcAddress so the stage0 bootstrap
//   does not need extra link flags.

#if !defined(_WIN32)
#include <fcntl.h>
#include <unistd.h>
#endif

#if defined(_WIN32)
// Missing errno values on some Windows UCRT configurations (keep syscall-style negative returns stable).
#ifndef EFAULT
#define EFAULT 14
#endif
#ifndef EIO
#define EIO 5
#endif
#endif

OrenValue oren_getentropy(OrenValue ptr, OrenValue len) {
    if (ptr.type != OREN_TYPE_INT || len.type != OREN_TYPE_INT) {
        oren_panic("getentropy expects (int ptr, int len)");
        return OREN_NIL;
    }
    long long p = ptr.as.int_val;
    long long n = len.as.int_val;
    if (n <= 0) return oren_int(0);
    if (p == 0) return oren_int(0 - (long long)EFAULT);

    unsigned char* out = (unsigned char*)(uintptr_t)p;

#if defined(_WIN32)
    if (n > 0x7fffffffLL) {
        return oren_int(0 - (long long)EINVAL);
    }

    // Resolve BCryptGenRandom lazily.
    HMODULE h = LoadLibraryA("bcrypt.dll");
    if (!h) {
        return oren_int(0 - (long long)EIO);
    }
    typedef long (WINAPI *BCryptGenRandomFn)(void* hAlgorithm, unsigned char* pbBuffer, unsigned long cbBuffer, unsigned long dwFlags);
    BCryptGenRandomFn fn = (BCryptGenRandomFn)(void*)GetProcAddress(h, "BCryptGenRandom");
    if (!fn) {
        return oren_int(0 - (long long)EIO);
    }
    // BCRYPT_USE_SYSTEM_PREFERRED_RNG = 0x00000002
    long st = fn(NULL, out, (unsigned long)n, 0x00000002UL);
    if (st != 0) {
        return oren_int(0 - (long long)EIO);
    }
    return oren_int(0);
#else
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) {
        return oren_int(0 - (long long)errno);
    }
    long long off = 0;
    while (off < n) {
        ssize_t rc = read(fd, out + off, (size_t)(n - off));
        if (rc < 0) {
            if (errno == EINTR) continue;
            int e = errno;
            close(fd);
            return oren_int(0 - (long long)e);
        }
        if (rc == 0) {
            close(fd);
            return oren_int(0 - (long long)EIO);
        }
        off += (long long)rc;
    }
    close(fd);
    return oren_int(0);
#endif
}
