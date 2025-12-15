#ifndef AVM_H
#define AVM_H

#include <stdint.h>
#include <stddef.h>

#define MAX_GLOBALS 256
#define MAX_FRAMES 65536

typedef enum {
    AVM_VAL_NIL = 0,
    AVM_VAL_INT = 1,
    AVM_VAL_FLOAT = 2,
    AVM_VAL_BOOL = 3,
    AVM_VAL_STRING = 4,
    AVM_VAL_LIST = 5,
    AVM_VAL_MAP = 6
} AvmType;

struct AvmList;
struct AvmMap;

typedef struct {
    AvmType type;
    union {
        int64_t i;
        double f;
        void* p;
        struct AvmList* l;
        struct AvmMap* m;
    } as;
} AvmValue;

typedef struct AvmList {
    AvmValue* items;
    int count;
    int capacity;
} AvmList;

typedef struct AvmMap {
    AvmValue* keys;
    AvmValue* values;
    int count;
    int capacity;
} AvmMap;

typedef struct {
    uint8_t* code;
    size_t code_len;
    AvmValue* constants;
    size_t const_count;
} AvmProgram;

typedef struct {
    int return_pc;
    int fp;
} AvmFrame;

typedef struct {
    AvmValue* stack;
    int sp; 
    int pc;
    int running;
    AvmProgram* prog;
    
    AvmValue globals[MAX_GLOBALS];
    AvmFrame frames[MAX_FRAMES];
    int frame_count;
    int fp; 

    // Capability model (rolling/unstable): bitmask of allowed native domains.
    // If zero, treat as "allow all" for now.
    uint64_t allowed_native_domains;
    
    int argc;
    char** argv;
} AvmVM;

AvmVM* avm_new();
void avm_free(AvmVM* vm);
void avm_load(AvmVM* vm, AvmProgram* prog);
void avm_run(AvmVM* vm);

#endif
