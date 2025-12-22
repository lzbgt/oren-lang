#include "runtime.h"

// This file is intentionally small.
//
// The C backend runtime is split into include chunks under `lib/runtime/*.inc`
// so individual parts remain reviewable without context overflow.
//
// NOTE: these are C preprocessor includes that build into a single translation unit.

#include "runtime/010_prelude.inc"
#include "runtime/020_threads_gc.inc"
#include "runtime/030_ops_compare.inc"
#include "runtime/040_lists_maps.inc"
#include "runtime/050_io_misc.inc"
