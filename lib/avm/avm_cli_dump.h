#ifndef AVM_CLI_DUMP_H
#define AVM_CLI_DUMP_H

#include "avm.h"
#include <stdio.h>

const char* avm_val_type_name(AvmValue v);
const char* avm_value_type_name(int t);
void dump_stack(FILE* out, AvmVM* vm, int limit);
void print_pause_json(FILE* out, AvmVM* vm);
void print_json_escaped_string(FILE* out, const char* s);

#endif
