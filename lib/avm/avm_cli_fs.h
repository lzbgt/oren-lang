#ifndef AVM_CLI_FS_H
#define AVM_CLI_FS_H

#include "avm.h"

void parse_fs_allow_prefixes(AvmVM* vm, const char* s);
void parse_fs_mounts(char*** out_virt, char*** out_host, int* out_count, const char* s);
int parse_fs_backend_kind(const char* s, int* out_kind);
int parse_proc_backend_kind(const char* s, int* out_kind);
int parse_net_backend_kind(const char* s, int* out_kind);

#endif
