#include "avm_internal.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <dirent.h>

#include <unistd.h>

// Determinism hardening (rolling):
// Avoid fused multiply-add / FP contraction differences across compilers/targets for AVM consensus hashing.
#pragma STDC FP_CONTRACT OFF
#ifdef __clang__
#pragma clang fp contract(off)
#endif

// Native capability dispatchers and record/replay logic live in a shared `.inc` for now.
// This translation unit provides the required helper functions via `avm_internal.h`.
#include "avm_native.inc"
