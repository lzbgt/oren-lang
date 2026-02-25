#ifndef AVM_CLI_DISASM_H
#define AVM_CLI_DISASM_H

#include "avm.h"
#include <stdio.h>

void disasm_program(FILE* out, const AvmProgram* prog, int show_consts);
void disasm_program_json(FILE* out, const AvmProgram* prog, int show_consts);

#endif
