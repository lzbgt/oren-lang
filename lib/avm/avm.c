#include "avm.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#define STACK_SIZE 16777216

char* my_strdup(const char* s) {
    char* d = malloc(strlen(s) + 1);
    strcpy(d, s);
    return d;
}

AvmValue avm_call_native(AvmVM* vm, uint16_t id, AvmValue* args, int nargs) {
    AvmValue res; res.type = AVM_VAL_NIL;
    switch(id) {
        case 0: { // oren_read_file
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                char* path = (char*)args[0].as.p;
                FILE* f = fopen(path, "rb");
                if (f) {
                    fseek(f, 0, SEEK_END);
                    long len = ftell(f);
                    fseek(f, 0, SEEK_SET);
                    char* buf = malloc(len + 1);
                    fread(buf, 1, len, f);
                    buf[len] = 0;
                    fclose(f);
                    res.type = AVM_VAL_STRING;
                    res.as.p = buf;
                }
            }
            break;
        }
        case 1: { // oren_write_file
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_STRING) {
                char* path = (char*)args[0].as.p;
                char* data = (char*)args[1].as.p;
                FILE* f = fopen(path, "wb");
                if (f) {
                    fwrite(data, 1, strlen(data), f);
                    fclose(f);
                }
            }
            break;
        }
        case 2: { // oren_system
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                int ret = system((char*)args[0].as.p);
                res.type = AVM_VAL_INT;
                res.as.i = ret;
            }
            break;
        }
        case 3: { // oren_args
            AvmList* list = malloc(sizeof(AvmList));
            list->count = vm->argc;
            list->capacity = vm->argc;
            list->items = malloc(sizeof(AvmValue) * vm->argc);
            for(int i=0; i<vm->argc; i++) {
                list->items[i].type = AVM_VAL_STRING;
                list->items[i].as.p = vm->argv[i];
            }
            res.type = AVM_VAL_LIST;
            res.as.l = list;
            break;
        }
        case 4: { // oren_env
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                char* val = getenv((char*)args[0].as.p);
                if (val) {
                    res.type = AVM_VAL_STRING;
                    res.as.p = my_strdup(val);
                }
            }
            break;
        }
        case 5: { // oren_exit
            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
                exit((int)args[0].as.i);
            }
            exit(0);
            break;
        }
        case 6: // oren_string_len
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                res.type = AVM_VAL_INT;
                res.as.i = strlen((char*)args[0].as.p);
            }
            break;
        case 7: // oren_string_char_at
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_INT) {
                char* s = (char*)args[0].as.p;
                int idx = (int)args[1].as.i;
                if (idx >= 0 && idx < strlen(s)) {
                    res.type = AVM_VAL_STRING;
                    char* buf = malloc(2);
                    buf[0] = s[idx];
                    buf[1] = 0;
                    res.as.p = buf;
                }
            }
            break;
        case 8: { // oren_string_slice
            if (nargs > 2 && args[0].type == AVM_VAL_STRING) {
                char* s = (char*)args[0].as.p;
                int start = (int)args[1].as.i;
                int end = (int)args[2].as.i;
                int len = strlen(s);
                if (start >= 0 && end <= len && start <= end) {
                    int sublen = end - start;
                    char* buf = malloc(sublen + 1);
                    strncpy(buf, s + start, sublen);
                    buf[sublen] = 0;
                    res.type = AVM_VAL_STRING;
                    res.as.p = buf;
                }
            }
            break;
        }
        case 9: { // oren_string_char_code_at
            if (nargs > 1 && args[0].type == AVM_VAL_STRING) {
                char* s = (char*)args[0].as.p;
                int idx = (int)args[1].as.i;
                if (idx >= 0 && idx < strlen(s)) {
                    res.type = AVM_VAL_INT;
                    res.as.i = (unsigned char)s[idx];
                }
            }
            break;
        }
        case 10: { // oren_int_to_string
            if (nargs > 0 && args[0].type == AVM_VAL_INT) {
                char buf[32];
                sprintf(buf, "%lld", args[0].as.i);
                res.type = AVM_VAL_STRING;
                res.as.p = my_strdup(buf);
            }
            break;
        }
        case 12: // oren_list_len
            if (nargs > 0 && args[0].type == AVM_VAL_LIST) {
                res.type = AVM_VAL_INT;
                res.as.i = args[0].as.l->count;
            }
            break;
        case 13: // oren_list_push
            if (nargs > 1 && args[0].type == AVM_VAL_LIST) {
                AvmList* list = args[0].as.l;
                if (list->count >= list->capacity) {
                    list->capacity *= 2;
                    list->items = realloc(list->items, sizeof(AvmValue) * list->capacity);
                }
                list->items[list->count++] = args[1];
            }
            break;
        case 14: { // oren_index_set
            if (nargs > 2 && args[0].type == AVM_VAL_LIST) {
                AvmList* list = args[0].as.l;
                int idx = (int)args[1].as.i;
                if (idx >= 0 && idx < list->count) {
                    list->items[idx] = args[2];
                }
            }
            break;
        }
        case 15: { // int_mod
            if (nargs > 1) {
                res.type = AVM_VAL_INT;
                res.as.i = args[0].as.i % args[1].as.i;
            }
            break;
        }
        case 16: { // oren_bytes_from_string
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                char* s = (char*)args[0].as.p;
                int len = strlen(s);
                AvmList* list = malloc(sizeof(AvmList));
                list->count = len;
                list->capacity = len;
                list->items = malloc(sizeof(AvmValue) * len);
                for(int i=0; i<len; i++) {
                    list->items[i].type = AVM_VAL_INT;
                    list->items[i].as.i = (unsigned char)s[i];
                }
                res.type = AVM_VAL_LIST;
                res.as.l = list;
            }
            break;
        }
        case 17: { // oren_write_bytes
            if (nargs > 1 && args[0].type == AVM_VAL_STRING && args[1].type == AVM_VAL_LIST) {
                char* path = (char*)args[0].as.p;
                AvmList* list = args[1].as.l;
                uint8_t* buf = malloc(list->count);
                for(int i=0; i<list->count; i++) {
                    buf[i] = (uint8_t)list->items[i].as.i;
                }
                FILE* f = fopen(path, "wb");
                if (f) {
                    fwrite(buf, 1, list->count, f);
                    fclose(f);
                }
                free(buf);
            }
            break;
        }
        case 18: { // oren_read_bytes
            if (nargs > 0 && args[0].type == AVM_VAL_STRING) {
                char* path = (char*)args[0].as.p;
                FILE* f = fopen(path, "rb");
                if (f) {
                    fseek(f, 0, SEEK_END);
                    long len = ftell(f);
                    fseek(f, 0, SEEK_SET);
                    if (len < 0) {
                        fclose(f);
                        break;
                    }
                    uint8_t* buf = NULL;
                    if (len > 0) {
                        buf = (uint8_t*)malloc((size_t)len);
                        if (!buf) {
                            fclose(f);
                            break;
                        }
                        size_t n = fread(buf, 1, (size_t)len, f);
                        if (n != (size_t)len) {
                            free(buf);
                            fclose(f);
                            break;
                        }
                    }
                    fclose(f);

                    AvmList* list = malloc(sizeof(AvmList));
                    list->count = (int)len;
                    list->capacity = (int)len;
                    if (len > 0) {
                        list->items = malloc(sizeof(AvmValue) * (size_t)len);
                        for (long i = 0; i < len; i++) {
                            list->items[i].type = AVM_VAL_INT;
                            list->items[i].as.i = (unsigned char)buf[i];
                        }
                    } else {
                        list->items = NULL;
                    }
                    free(buf);

                    res.type = AVM_VAL_LIST;
                    res.as.l = list;
                }
            }
            break;
        }
        // TODO: Implement others
        default:
            printf("Unknown native id: %d\n", id);
            break;
    }
    return res;
}

// Rolling ABI: CALL_NATIVE2(domain, op, nargs)
// For now, CORE domain (0) maps op -> legacy native id.
static AvmValue avm_call_native2(AvmVM* vm, uint8_t domain, uint16_t op, AvmValue* args, int nargs) {
    // Capability check (rolling behavior):
    // - allowed_native_domains == 0 => allow all (bootstrap default)
    // - otherwise require bit set for domain
    if (vm->allowed_native_domains != 0) {
        uint64_t mask = 1ULL << (domain & 63);
        if ((vm->allowed_native_domains & mask) == 0) {
            AvmValue res; res.type = AVM_VAL_NIL;
            return res;
        }
    }

    // Domain 0: CORE (bootstrap mapping: op == legacy native id)
    if (domain == 0) return avm_call_native(vm, op, args, nargs);

    // Domain 1: FS (filesystem). Map op -> legacy ids for now.
    // This is a rolling ABI: domain/op tables may evolve quickly.
    if (domain == 1) {
        switch (op) {
            case 0: return avm_call_native(vm, 0, args, nargs);  // read_file
            case 1: return avm_call_native(vm, 1, args, nargs);  // write_file
            case 2: return avm_call_native(vm, 17, args, nargs); // write_bytes
            case 3: return avm_call_native(vm, 18, args, nargs); // read_bytes
            default: break;
        }
    }

    // Unknown/unsupported domain in bootstrap.
    AvmValue res; res.type = AVM_VAL_NIL;
    return res;
}

AvmVM* avm_new() {
    AvmVM* vm = (AvmVM*)malloc(sizeof(AvmVM));
    vm->stack = (AvmValue*)malloc(sizeof(AvmValue) * STACK_SIZE);
    vm->sp = 0;
    vm->pc = 0;
    vm->running = 0;
    vm->prog = NULL;
    vm->fp = 0;
    vm->frame_count = 0;
    vm->allowed_native_domains = 0;
    for(int i=0; i<MAX_GLOBALS; i++) vm->globals[i].type = AVM_VAL_NIL;
    return vm;
}

void avm_free(AvmVM* vm) {
    if (vm->stack) free(vm->stack);
    free(vm);
}

void avm_load(AvmVM* vm, AvmProgram* prog) {
    vm->prog = prog;
    vm->pc = 0;
    vm->sp = 0;
    vm->fp = 0;
    vm->frame_count = 0;
}

void avm_run(AvmVM* vm) {
    if (!vm->prog) return;
    vm->running = 1;
    uint8_t* code = vm->prog->code;
    
    while (vm->running && vm->pc < vm->prog->code_len) {
        uint8_t op = code[vm->pc++];
        // printf("PC: %d, OP: %d, SP: %d, FP: %d\n", vm->pc-1, op, vm->sp, vm->fp);
        switch (op) {
            case 0x00: // NOP
                break;
            case 0x01: // HALT
                vm->running = 0;
                break;
            case 0x02: { // PUSH_CONST u16
                if (vm->pc + 2 > vm->prog->code_len) { vm->running = 0; break; }
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx < vm->prog->const_count) {
                    vm->stack[vm->sp++] = vm->prog->constants[idx];
                }
                break;
            }
            case 0x03: // POP
                if (vm->sp > 0) vm->sp--;
                break;
            case 0x04: { // LOAD_LOCAL u8
                uint8_t idx = code[vm->pc++];
                // Check bounds?
                vm->stack[vm->sp++] = vm->stack[vm->fp + idx];
                break;
            }
            case 0x05: { // STORE_LOCAL u8
                uint8_t idx = code[vm->pc++];
                vm->stack[vm->fp + idx] = vm->stack[--vm->sp];
                break;
            }
            case 0x06: { // LOAD_GLOBAL u16
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx < MAX_GLOBALS) vm->stack[vm->sp++] = vm->globals[idx];
                break;
            }
            case 0x07: { // STORE_GLOBAL u16
                uint16_t idx = code[vm->pc++];
                idx |= (uint16_t)code[vm->pc++] << 8;
                if (idx < MAX_GLOBALS) vm->globals[idx] = vm->stack[--vm->sp];
                break;
            }
            case 0x10: { // ADD
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res;
                    res.type = AVM_VAL_INT; 
                    res.as.i = a.as.i + b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x11: { // SUB
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res;
                    res.type = AVM_VAL_INT; 
                    res.as.i = a.as.i - b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x12: { // LT
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res;
                    res.type = AVM_VAL_INT;
                    res.as.i = (a.as.i < b.as.i) ? 1 : 0;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x13: { // EQ
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    if (a.type != b.type) res.as.i = 0;
                    else if (a.type == AVM_VAL_INT) res.as.i = (a.as.i == b.as.i);
                    else if (a.type == AVM_VAL_STRING) res.as.i = (strcmp((char*)a.as.p, (char*)b.as.p) == 0);
                    else res.as.i = 0;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x14: { // NEQ
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    if (a.type != b.type) res.as.i = 1;
                    else if (a.type == AVM_VAL_INT) res.as.i = (a.as.i != b.as.i);
                    else if (a.type == AVM_VAL_STRING) res.as.i = (strcmp((char*)a.as.p, (char*)b.as.p) != 0);
                    else res.as.i = 1;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x15: { // GT
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = (a.as.i > b.as.i);
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x16: { // LTE
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = (a.as.i <= b.as.i);
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x17: { // GTE
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = (a.as.i >= b.as.i);
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x18: { // BITAND
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = a.as.i & b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x19: { // BITOR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = a.as.i | b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x1A: { // BITXOR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = a.as.i ^ b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x1B: { // SHL
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = a.as.i << b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x1C: { // SHR
                if (vm->sp >= 2) {
                    AvmValue b = vm->stack[--vm->sp];
                    AvmValue a = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_INT;
                    res.as.i = a.as.i >> b.as.i;
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x20: { // PRINT
                if (vm->sp > 0) {
                    AvmValue v = vm->stack[--vm->sp];
                    if (v.type == AVM_VAL_INT) printf("%lld\n", v.as.i);
                    else if (v.type == AVM_VAL_FLOAT) printf("%f\n", v.as.f);
                    else if (v.type == AVM_VAL_STRING) printf("%s\n", (char*)v.as.p);
                    else printf("?\n");
                }
                break;
            }
            case 0x30: { // JMP i16
                int16_t off = code[vm->pc++];
                off |= (int16_t)code[vm->pc++] << 8;
                vm->pc += off;
                break;
            }
            case 0x31: { // JMP_IF i16
                int16_t off = code[vm->pc++];
                off |= (int16_t)code[vm->pc++] << 8;
                if (vm->sp > 0) {
                    AvmValue cond = vm->stack[--vm->sp];
                    int truthy = 0;
                    if (cond.type == AVM_VAL_INT && cond.as.i != 0) truthy = 1;
                    else if (cond.type == AVM_VAL_BOOL && cond.as.i != 0) truthy = 1;
                    
                    if (truthy) vm->pc += off;
                }
                break;
            }
            case 0x38: { // CALL u16_addr u8_nargs
                uint16_t addr = code[vm->pc++];
                addr |= (uint16_t)code[vm->pc++] << 8;
                uint8_t nargs = code[vm->pc++];
                
                if (vm->frame_count > 65000) {
                    printf("CALL addr: %d, depth: %d\n", addr, vm->frame_count);
                }
                
                if (vm->frame_count >= MAX_FRAMES) {
                    printf("Stack overflow (depth %d)\n", vm->frame_count);
                    vm->running = 0;
                    break;
                }
                
                vm->frames[vm->frame_count].return_pc = vm->pc;
                vm->frames[vm->frame_count].fp = vm->fp;
                vm->frame_count++;
                
                vm->fp = vm->sp - nargs;
                vm->pc = addr;
                break;
            }
            case 0x39: { // RET
                if (vm->frame_count == 0) {
                    vm->running = 0;
                    break;
                }
                
                AvmValue ret_val;
                ret_val.type = AVM_VAL_NIL;
                if (vm->sp > vm->fp) {
                     ret_val = vm->stack[--vm->sp];
                }
                
                vm->frame_count--;
                vm->pc = vm->frames[vm->frame_count].return_pc;
                int old_fp = vm->frames[vm->frame_count].fp;
                
                vm->sp = vm->fp;
                vm->fp = old_fp;
                
                vm->stack[vm->sp++] = ret_val;
                break;
            }
            case 0x3A: { // CALL_NATIVE
                uint16_t id = code[vm->pc++];
                id |= (uint16_t)code[vm->pc++] << 8;
                uint8_t nargs = code[vm->pc++];
                
                AvmValue args[16];
                for(int i=nargs-1; i>=0; i--) {
                    args[i] = vm->stack[--vm->sp];
                }
                
                AvmValue res = avm_call_native(vm, id, args, nargs);
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x3B: { // CALL_NATIVE2: u8 domain, u16 op, u8 nargs
                uint8_t domain = code[vm->pc++];
                uint16_t op = code[vm->pc++];
                op |= (uint16_t)code[vm->pc++] << 8;
                uint8_t nargs = code[vm->pc++];

                AvmValue args[16];
                for (int i = nargs - 1; i >= 0; i--) {
                    args[i] = vm->stack[--vm->sp];
                }

                AvmValue res = avm_call_native2(vm, domain, op, args, nargs);
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x40: { // NEW_LIST u16_count
                uint16_t count = code[vm->pc++];
                count |= (uint16_t)code[vm->pc++] << 8;
                
                AvmList* list = (AvmList*)malloc(sizeof(AvmList));
                list->count = count;
                list->capacity = count + 8;
                list->items = (AvmValue*)malloc(sizeof(AvmValue) * list->capacity);
                
                for(int i=count-1; i>=0; i--) {
                    list->items[i] = vm->stack[--vm->sp];
                }
                
                AvmValue res;
                res.type = AVM_VAL_LIST;
                res.as.l = list;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x41: { // NEW_MAP u16_count
                uint16_t count = code[vm->pc++];
                count |= (uint16_t)code[vm->pc++] << 8;
                
                AvmMap* map = (AvmMap*)malloc(sizeof(AvmMap));
                map->count = count;
                map->capacity = count + 8;
                map->keys = (AvmValue*)malloc(sizeof(AvmValue) * map->capacity);
                map->values = (AvmValue*)malloc(sizeof(AvmValue) * map->capacity);
                
                for(int i=count-1; i>=0; i--) {
                    map->values[i] = vm->stack[--vm->sp];
                    map->keys[i] = vm->stack[--vm->sp];
                }
                
                AvmValue res;
                res.type = AVM_VAL_MAP;
                res.as.m = map;
                vm->stack[vm->sp++] = res;
                break;
            }
            case 0x42: { // GET_INDEX
                if (vm->sp >= 2) {
                    AvmValue key = vm->stack[--vm->sp];
                    AvmValue obj = vm->stack[--vm->sp];
                    AvmValue res; res.type = AVM_VAL_NIL;
                    
                    if (obj.type == AVM_VAL_LIST && key.type == AVM_VAL_INT) {
                        int i = (int)key.as.i;
                        if (i >= 0 && i < obj.as.l->count) {
                            res = obj.as.l->items[i];
                        }
                    } else if (obj.type == AVM_VAL_MAP) {
                        for(int i=0; i<obj.as.m->count; i++) {
                            AvmValue k = obj.as.m->keys[i];
                            int match = 0;
                            if (k.type == key.type) {
                                if (k.type == AVM_VAL_INT) match = (k.as.i == key.as.i);
                                else if (k.type == AVM_VAL_STRING) match = (strcmp((char*)k.as.p, (char*)key.as.p) == 0);
                            }
                            if (match) {
                                res = obj.as.m->values[i];
                                break;
                            }
                        }
                    }
                    vm->stack[vm->sp++] = res;
                }
                break;
            }
            case 0x43: { // SET_INDEX
                if (vm->sp >= 3) {
                    AvmValue val = vm->stack[--vm->sp];
                    AvmValue key = vm->stack[--vm->sp];
                    AvmValue obj = vm->stack[--vm->sp];
                    
                    if (obj.type == AVM_VAL_LIST && key.type == AVM_VAL_INT) {
                        int i = (int)key.as.i;
                        if (i >= 0 && i < obj.as.l->count) {
                            obj.as.l->items[i] = val;
                        } else if (i == obj.as.l->count) {
                            if (obj.as.l->count < obj.as.l->capacity) {
                                obj.as.l->items[obj.as.l->count++] = val;
                            }
                        }
                    } else if (obj.type == AVM_VAL_MAP) {
                        int found = 0;
                        for(int i=0; i<obj.as.m->count; i++) {
                            AvmValue k = obj.as.m->keys[i];
                            int match = 0;
                            if (k.type == key.type) {
                                if (k.type == AVM_VAL_INT) match = (k.as.i == key.as.i);
                                else if (k.type == AVM_VAL_STRING) match = (strcmp((char*)k.as.p, (char*)key.as.p) == 0);
                            }
                            if (match) {
                                obj.as.m->values[i] = val;
                                found = 1;
                                break;
                            }
                        }
                        if (!found && obj.as.m->count < obj.as.m->capacity) {
                            obj.as.m->keys[obj.as.m->count] = key;
                            obj.as.m->values[obj.as.m->count] = val;
                            obj.as.m->count++;
                        }
                    }
                }
                break;
            }
            default:
                printf("Unknown opcode: %d\n", op);
                vm->running = 0;
                break;
        }
    }
}
