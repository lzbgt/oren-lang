#ifndef AVM_CLI_VERIFY_H
#define AVM_CLI_VERIFY_H

#include "avm.h"
#include <stdint.h>

typedef struct {
    int ok;
    char msg[512];
    uint64_t used_domains_mask;
} VerifyResult;

VerifyResult verify_program(const AvmProgram* prog, int strict_legacy);

#endif
