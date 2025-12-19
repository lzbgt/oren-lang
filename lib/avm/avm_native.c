#include "avm_internal.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <dirent.h>

#include <unistd.h>

// SIMD build-time gating (rolling; runtime opt-in via AVM_ENABLE_SIMD=1):
// - Compiles NEON paths only when targeting arm64 with NEON available.
// - SIMD must never change semantics; scalar fallback remains authoritative.
#if defined(__aarch64__) && (defined(__ARM_NEON) || defined(__ARM_NEON__))
#define AVM_HAS_NEON 1
#include <arm_neon.h>
#else
#define AVM_HAS_NEON 0
#endif

// Determinism hardening (rolling):
// Avoid fused multiply-add / FP contraction differences across compilers/targets for AVM consensus hashing.
#pragma STDC FP_CONTRACT OFF
#ifdef __clang__
#pragma clang fp contract(off)
#endif

// Native capability dispatchers and record/replay logic live in a shared `.inc` for now.
// This translation unit provides the required helper functions via `avm_internal.h`.
#include "avm_native.inc"
