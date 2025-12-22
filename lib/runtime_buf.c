#include "runtime.h"

// This file is intentionally small.
//
// The C backend runtime buffer implementation is split into include chunks under
// `lib/runtime_buf/*.inc` so individual parts remain reviewable without context overflow.
//
// NOTE: these are C preprocessor includes that build into a single translation unit
// (no link-time boundary), so behavior and inlining remain unchanged.

#include "runtime_buf/010_prelude.inc"
#include "runtime_buf/020_basic.inc"
#include "runtime_buf/030_arith.inc"
#include "runtime_buf/040_dot_gemm.inc"
#include "runtime_buf/050_reduce_axpy.inc"
