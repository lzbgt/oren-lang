    int i = 1;
    while (i < argc) {
        if (strcmp(argv[i], "--") == 0) {
            prog_args_start = i + 1;
            break;
        }
        if (strcmp(argv[i], "--snapshot-in") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --snapshot-in\n"); return 1; }
            snap_in = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--snapshot-out") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --snapshot-out\n"); return 1; }
            snap_out = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--step-limit") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --step-limit\n"); return 1; }
            step_limit = strtoull(argv[i + 1], NULL, 10);
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--timeout-ms") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --timeout-ms\n"); return 1; }
            timeout_ms_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--call-depth-max") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --call-depth-max\n"); return 1; }
            call_depth_max_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--task-quantum") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --task-quantum\n"); return 1; }
            task_quantum_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--print-state-hash") == 0) {
            print_state_hash = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-result-hash") == 0) {
            print_result_hash = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-trace-hash") == 0) {
            print_trace_hash = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-trace-bytes-hex") == 0) {
            print_trace_bytes_hex = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-record-log-hex") == 0) {
            print_record_log_hex = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-mem-stats") == 0) {
            print_mem_stats = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-rss") == 0) {
            print_rss = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-run-json") == 0) {
            print_run_json = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-policy") == 0) {
            print_policy = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-policy-json") == 0) {
            print_policy_json = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-job") == 0) {
            print_job = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-job-json") == 0) {
            print_job_json = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--inspect") == 0) {
            inspect = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--inspect-json") == 0) {
            inspect_json = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--verify-strict") == 0) {
            verify_strict = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--capsule") == 0 || strcmp(argv[i], "--untrusted") == 0) {
            capsule = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--deny-by-default") == 0) {
            deny_by_default = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--allow-domains") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --allow-domains\n"); return 1; }
            allow_domains_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--fs-allow-prefixes") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --fs-allow-prefixes\n"); return 1; }
            fs_allow_prefixes_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--fs-mounts") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --fs-mounts\n"); return 1; }
            fs_mounts_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--fs-mounts-read") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --fs-mounts-read\n"); return 1; }
            fs_mounts_read_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--fs-mounts-write") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --fs-mounts-write\n"); return 1; }
            fs_mounts_write_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--fs-backend") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --fs-backend\n"); return 1; }
            fs_backend_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--proc-backend") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --proc-backend\n"); return 1; }
            proc_backend_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--proc-exit-code") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --proc-exit-code\n"); return 1; }
            proc_exit_code_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--proc-fixtures-hex") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --proc-fixtures-hex\n"); return 1; }
            proc_fixtures_hex_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--net-backend") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --net-backend\n"); return 1; }
            net_backend_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--net-fixtures-hex") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --net-fixtures-hex\n"); return 1; }
            net_fixtures_hex_cli = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--require-sig") == 0) {
            require_sig = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--require-cert-chain") == 0) {
            require_sig = 1;
            require_cert_chain = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--trusted-pubkey") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --trusted-pubkey\n"); return 1; }
            if (trusted_pubkey_cli_count >= 16) { fprintf(stderr, "Too many --trusted-pubkey entries (cap=16)\n"); return 1; }
            trusted_pubkey_cli_list[trusted_pubkey_cli_count++] = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--trusted-pubkey-hex") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --trusted-pubkey-hex\n"); return 1; }
            if (trusted_pubkey_hex_cli_count >= 16) { fprintf(stderr, "Too many --trusted-pubkey-hex entries (cap=16)\n"); return 1; }
            trusted_pubkey_hex_cli_list[trusted_pubkey_hex_cli_count++] = argv[i + 1];
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--disasm") == 0) {
            disasm = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--disasm-consts") == 0) {
            disasm = 1;
            disasm_consts = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--disasm-json") == 0) {
            disasm = 1;
            disasm_json = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--disasm-consts-json") == 0) {
            disasm = 1;
            disasm_json = 1;
            disasm_json_consts = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--trace") == 0) {
            trace = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--trace-limit") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --trace-limit\n"); return 1; }
            trace = 1;
            trace_limit = strtoull(argv[i + 1], NULL, 10);
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--print-stack") == 0) {
            print_stack = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--print-pause-json") == 0) {
            print_pause_json_flag = 1;
            i += 1;
            continue;
        }
        if (strcmp(argv[i], "--breakpc") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --breakpc\n"); return 1; }
            long pc = strtol(argv[i + 1], NULL, 10);
            if (pc < 0 || pc > INT_MAX) { fprintf(stderr, "Invalid --breakpc value\n"); return 1; }
            if (break_pc_count >= break_pc_cap) {
                int nc = break_pc_cap ? break_pc_cap * 2 : 8;
                int* np = (int*)realloc(break_pcs, sizeof(int) * (size_t)nc);
                if (!np) { fprintf(stderr, "OOM\n"); return 1; }
                break_pcs = np;
                break_pc_cap = nc;
            }
            break_pcs[break_pc_count++] = (int)pc;
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--repeat") == 0) {
            if (i + 1 >= argc) { fprintf(stderr, "Missing value for --repeat\n"); return 1; }
            long n = strtol(argv[i + 1], NULL, 10);
            if (n <= 0 || n > 100000000) { fprintf(stderr, "Invalid --repeat value\n"); return 1; }
            repeat = (int)n;
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fputs(AVM_HELP_TEXT, stdout);
            free(break_pcs);
            return 0;
        }
        if (argv[i][0] == '-') {
            fprintf(stderr, "Unknown arg: %s\n", argv[i]);
            return 1;
        }
        obc_path = argv[i];
        i++;
    }

    if (!obc_path) {
        fputs(AVM_HELP_TEXT, stdout);
        free(break_pcs);
        return 1;
    }
    if (prog_args_start >= 0 && prog_args_start <= argc) {
        prog_argc = argc - prog_args_start;
        prog_argv = argv + prog_args_start;
    }
    if (repeat > 1 && (snap_in || snap_out)) {
        fprintf(stderr, "--repeat is not compatible with --snapshot-in/--snapshot-out (for now)\n");
        free(break_pcs);
        return 1;
    }
