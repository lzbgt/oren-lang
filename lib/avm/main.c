#include "avm.h"
#include <stdio.h>
#include <stdlib.h>

uint8_t* read_file(const char* path, size_t* len) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    *len = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t* buf = (uint8_t*)malloc(*len);
    fread(buf, 1, *len, f);
    fclose(f);
    return buf;
}

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: avm <file.obc>\n");
        return 1;
    }
    size_t len;
    uint8_t* data = read_file(argv[1], &len);
    if (!data) {
        printf("Failed to read file\n");
        return 1;
    }
    
    // Parse OBC
    // Header: CD 0E
    if (len < 2 || data[0] != 0xCD || data[1] != 0x0E) {
        printf("Invalid magic\n");
        return 1;
    }
    
    // Const count (u16)
    size_t pos = 2;
    uint16_t n_consts = data[pos] | (data[pos+1] << 8);
    pos += 2;
    
    AvmValue* consts = (AvmValue*)malloc(sizeof(AvmValue) * n_consts);
    for (int i = 0; i < n_consts; i++) {
        uint8_t type = data[pos++];
        if (type == 0) { // NIL
            consts[i].type = AVM_VAL_NIL;
        }
        if (type == 1) { // INT
            int64_t val = 0;
            for (int k=0; k<8; k++) {
                val |= (int64_t)data[pos++] << (k*8);
            }
            consts[i].type = AVM_VAL_INT;
            consts[i].as.i = val;
        }
        if (type == 4) { // STRING
            uint16_t slen = (uint16_t)data[pos] | ((uint16_t)data[pos + 1] << 8);
            pos += 2;
            char* s = (char*)malloc((size_t)slen + 1);
            for (uint16_t k = 0; k < slen; k++) s[k] = (char)data[pos++];
            s[slen] = 0;
            consts[i].type = AVM_VAL_STRING;
            consts[i].as.p = s;
        }
        // TODO: Other types
    }
    
    // Code
    uint8_t* code = data + pos;
    size_t code_len = len - pos;
    
    AvmProgram prog;
    prog.code = code;
    prog.code_len = code_len;
    prog.constants = consts;
    prog.const_count = n_consts;
    
    AvmVM* vm = avm_new();
    vm->argc = argc - 1;
    vm->argv = argv + 1;
    avm_load(vm, &prog);
    avm_run(vm);
    avm_free(vm);
    
    return 0;
}
