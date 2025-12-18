#include "avm_internal.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <dirent.h>

#include <unistd.h>

// Native capability dispatchers and record/replay logic live in a shared `.inc` for now.
// This translation unit provides the required helper functions via `avm_internal.h`.
#include "avm_native.inc"
