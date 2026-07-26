# Bleeding-Edge Goals and Current Tasks

**Last updated:** 2026-06-01

This file is the concise task view. Detailed implementation status lives in
`docs/STATUS.md`; dated investigation notes live in `project-doc/`.

## Goals

- Deterministic execution with capability-gated effects across native, C, and AVM.
- Cross-backend semantic parity guarded by fixtures and targeted verification.
- Native performance approaching C on hot loops and allocation-heavy workloads.
- Production-grade runtime robustness: allocator, GC/reuse, scheduler, and effect domains.
- AVM portable bytecode suitable for sandboxed execution once embedding and release
  gates are mature.
- Documentation and tooling that stay small enough to navigate quickly.

## P0 / W5

1. **Runtime robustness and allocator correctness**
   - Keep `make verify-runtime-robustness` and `make test` green.
   - 2026-05-29: native quick `Error 139` is fixed; runtime identity checks now avoid recursive string-aware equality.
   - Treat GC/reuse/list-header integrity as a blocking production concern.

2. **Native performance parity**
   - Track hot-loop and allocation gates through the existing performance scripts.
   - Do not retain local codegen probes unless profiles prove aggregate wall-time wins.
   - Current compiler byte-output cleanup routes full-string bytecode constants
     and ARM64 Mach-O string-table names through byte-builder string extension
     instead of residual per-byte string-read loops, and that central helper now
     bulk-copies validated string spans into builder `u8_buf` storage.
   - Current ASTBIN and scan-cache save cleanup bulk-copies validated strings
     directly into reserved `u8_buf` spans instead of per-byte string-read
     loops in those compiler cache writers.
   - Current PE/ELF and native compiler C-string output cleanup routes
     NUL-terminated string appends through shared byte-builder string+zero
     extension.
   - Current HPACK raw string-literal output uses direct string-slice copies into
     the encoded header-block `u8_buf`, with RFC raw-literal fixture coverage.
   - Current `std:net/url` output uses direct string-slice copies for concat
     spans plus percent encode/decode unchanged runs, leaving only transformed
     `%XX` bytes and query `+` spaces explicit.
   - Current `std:bytes.to_hex` emits lowercase digit bytes arithmetically
     instead of indexing a digit string for each output nibble.
   - Current native compiler data-section cleanup routes ARM64/x64 alignment and
     fixed table reservations through exact byte-builder zero-extension spans.
   - Current ARM64 native local-function code alignment uses byte-builder
     zero-extension spans instead of repeated zero-byte code padding.
   - Current x64 split-module cleanup also routes string-batch, top-level
     synthetic global, and debug-root table alignment through the same helper.
   - Current PE byte-output cleanup routes export/header/raw-section padding
     through exact byte-builder zero-extension helpers.
   - Current PE import-name cleanup routes hint/name entry alignment through
     `_pe_align(rdata, 2)` instead of repeated one-byte zero-pad branches.
   - Current Mach-O/ELF byte-output cleanup routes final executable padding
     through existing alignment helpers and exact zero-extension spans.
   - Current ELF string-table cleanup routes interpreter strings, dynstr/shstr
     leading NULs, and ARM64 data C strings through shared string+zero or
     zero-span helpers instead of separate string append plus zero-byte pushes.
   - Current ARM64 Mach-O cleanup routes load-command, string-table, and final
     text/data prefix padding through `_macho_pad_to_len`/`_macho_align`.
   - Current ARM64 Mach-O import GOT cleanup aligns data with `_macho_align`
     before reserving import pointer slots with exact zero extension.
   - Current ELF page-padding cleanup extends the output prefix directly with
     exact zero spans instead of allocating and copying a temporary `code_pad`
     builder.
   - Current ARM64 native data cleanup routes C-string literal append, panic
     string alignment, global slots, and C-string table alignment through
     byte-builder span helpers.
   - Current runtime-object sidecar cleanup routes debug-name alignment through
     byte-builder zero-extension instead of per-byte zero pushes.

3. **Tagged value convergence**
   - Preserve cross-backend `oren_type_tag`, equality, truthiness, and panic parity.
   - Continue migration through compatibility fixtures rather than unguarded ABI rewrites.

## P1 / W4

1. **AVM iOS embeddability and compiler-in-AVM release gate**
   - Current verdict: iOS `LibAVM.xcframework` packaging, macOS desktop
     `LibAVM.xcframework` packaging, Linux x64 static `LibAVM` packaging, Windows
     x64 static `LibAVM` packaging, and a C embedder API now exist. The public API includes argv, VFS input/output,
     VirtualNET fixture, VirtualPROC fixture/default, deterministic TIME by default,
     stdout-capture helpers required by app-host compile/run bridges, plus a
     one-shot `avm_runner` API for the common run/capture lifecycle.
     `make verify-libavm-ios` now proves host compile-to-OBC, iOS C smoke linkage,
     host embedder
     argv/VFS/TIME/VNET/VPROC load/run, captured stdout retrieval/clear, and a
     nested compiler-in-AVM stdlib-OBC compile/run smoke, a shared app-scale
     CompilerKit fixture covering trait receiver methods, struct field chains,
     codec method chains, buffer/linalg APIs, and Scene3D package authoring,
     plus the public
     `OrenAVMCompilerKit` SDK helper that compiles source to OBC through AVM
     VirtualFS/argv.
   - Desktop SDK gate: `make verify-libavm-desktop` builds macOS arm64/x86_64
     `LibAVM.xcframework` slices, checks public embedder symbols in both archives,
     and runs local host C, Swift, and `avm_runner` embedders against OBC bytes.
   - Linux x64 SDK gate: `make verify-libavm-linux-x64` cross-builds the C embedder
     static library, exports headers/module-map/pkg-config metadata, checks
     x86_64 ELF output and embedder/runner symbols, and compiles a Linux x64 host
     `avm_runner` smoke. Runtime execution is QEMU-gated when an emulator is present.
   - Windows x64 SDK gate: `make verify-libavm-windows-x64` cross-builds the C
     embedder static library, exports headers/module-map metadata, checks
     amd64 COFF output and embedder/runner symbols, and compiles a Windows x64 host
     `avm_runner` smoke. Runtime execution is Wine-gated when available.
   - Native x64 compile gate: `make verify-native-x64-compile` now prewarms
     Linux/Windows x64 runtime-object seeds through an explicit bounded
     cross-compiler compatibility probe, avoiding slow stage2 cold-build
     prewarm hangs while preserving stage2 output checks.
	     The compiler now uses `oren.oren` as the single root for x64 self-host
	     compiler artifacts as well: import-level `@cfg(arch=...)` prunes inactive
	     backend imports during dependency discovery, replacing the former
	     `oren_x64.oren` / `compiler_x64.oren` wrapper files while preserving
	     lightweight arm64 backend stubs for x64 compiler builds.
		     x64 native emit now contributes build/codegen/ELF milestones to
		     `OREN_TRACE_BUILD_PHASES_PATH`. Cached x64 runtime-object fixups now
		     persist byte-native u64 sidecars for runtime call targets, RIP-data
		     patches, code-lea patches, and function-object pointers. Local
		     steady-state probing reduced cached runtime-object ELF replay from
		     roughly 31s to about 0.53s; remaining tiny-build emit time is now in
			     local/entry ELF fixups and final binary assembly. x64 now records
			     global-root name/offset/runtime lists in compiler ctx and new
			     runtime-object metadata, then emits entry root registration through
			     one offset-table loop instead of one `lea+call` sequence per root.
				     Cached x64 runtime-object entries now persist root/global metadata
				     sidecars and lazily derive them from legacy metadata once, so direct
				     unified `oren.oren` x64 self-host builds can adopt root lists without
				     rebuilding the runtime object or walking the legacy globals map in the
				     hot apply path. x64 function/body phase markers now narrow synthesized
				     `__top_level__` global initializer emission precisely. Integer constants
				     (including signed prefix literals and namespace aliases) plus nil/bool
				     singleton globals are materialized directly in `.data`; string global
				     `.data` relocation is explicit opt-in via `OREN_X64_GLOBAL_STRINGS_IN_DATA=1`
				     because capped self-host probes still show it dominating
					     `x64.codegen.top_globals.user_slots`. Default string literal global
					     assignments instead use a non-dedup byte-native cstr append path inside
					     synthesized `__top_level__`. Phase summaries count top-level string
					     fast-path candidates/hits plus direct global-slot path counts, and
					     `OREN_TRACE_X64_TOP_GLOBAL_SLOT_SLOW_MS` enables bounded per-slot
					     slow records for opt-in `.data` relocation probes. The no-dedup
					     cstr append path now extends the data builder directly from strings
					     instead of allocating temporary byte buffers. A focused x64
					     top-level string-global compile fixture guards the fast path.
								     Zero-result lambda collection now skips the full statement walk when no
								     local function/lambda candidates were found. Empty map/list globals avoid
								     static `.data` materialization but now lower through table-driven
								     `__top_level__` runtime-allocation batches, keeping mutable container
									     semantics heap/GC-safe without per-global emitter work. Bounded slow-function rankings now persist in
								     `OREN_TRACE_BUILD_PHASES_PATH` logs. Phase logs also include
								     `link.parse_module.start`, so capped self-host probes identify the active
								     module even when it does not finish before timeout. Serial/thread module
								     parse profiling now includes `link.parse_parallel.*` setup markers and
								     per-module thread/fork worker markers. The current x64 self-host evidence
									     shows thread-mode parsing (`fork=0`) with cold module-cache reads
									     (`cache_hit=0`) and top completed costs in `lib/compiler/compiler.oren`
									     (~15.8s), `parser_parse.oren` (~6.7s), and `codegen_bytecode.oren` (~6.1s);
									     forced fork was rejected because compiler-shaped ASTBIN worker encoding
									     still stalls early. Next work should recover warm thread-mode module-cache
									     hits or reduce parser throughput before returning to x64 user-function
									     emit. Module discovery now logs bounded
									     `link.discover_module.done` path/scan/dependency attribution, and
									     repo-owned `lib/compiler/**` plus `lib/std/**` files use header-only
									     import scanning after a repo scan proved all 1495 Oren files keep
										     imports before code. Include-aggregator detection now exits at the first
									     real code line for ordinary children, so capped x64 self-host discovery
									     dropped from roughly 45.7s to 26.8s after header scanning and then to
									     about 0.675s after aggregator early exit. The Linux x64 syscall intrinsic
									     dispatcher is split into fs/proc/misc helper bodies; the capped x64
									     self-host parse profile for `x64_native_program.oren` moved from about
									     41.4s total / 30.4s parse to 38.2s total / 27.8s parse, shifting the hot
									     parser body from `_emit_intrinsic_sys_linux_x64` to
									     `native_compile_program_x64`. `native_compile_program_x64` now delegates
									     debug metadata and entry global-root table emission to helpers; total x64
									     module parse stayed essentially flat in the capped profile (~38.5s), and
									     the exposed parser target was `_emit_eval_int_to_rax`. `_emit_eval_int_to_rax`
									     now delegates prefix and infix expression lowering to helpers, moving capped
									     `x64_native_program.oren` parse from about 38.5s total / 27.9s parse to
									     37.5s total / 27.3s parse and exposing `native_compile_program_x64` again
									     as the largest parser body. `native_compile_program_x64` now also delegates
									     entry runtime bootstrap emission and the user-function compile loop to
									     helper bodies; the valid reduced-arity helper shape keeps compiler-in-AVM
									     verification compatible and leaves the final capped `x64_native_program.oren`
									     profile at about 37.8s total / 27.2s parse, with
									     `native_compile_program_x64` narrowed to about 1.09s as the exposed hot
									     parser body. X64 compile diagnostic/trace option parsing is now isolated
										     in a zero-argument helper plus local unpacking, avoiding another wide OBC
										     call; the capped profile now shows `x64_native_program.oren` at about
										     38.0s total / 27.4s parse, with `_emit_eval_int_to_rax` exposed again
										     at about 1.06s. X64 call expression lowering now lives in a dedicated
										     `_emit_eval_call_expr_to_rax` helper, and native program callable-use
										     collection plus lambda wrapper synthesis are split out of
										 `native_compile_program_x64`; the capped profile now shows
										 `x64_native_program.oren` at about 37.9s total / 27.4s parse, with the
										 exposed parser body shifted to `_emit_ops_in_fn` at about 954ms. The
										 x64 op emitter now delegates while/for lowering and string-global batch
										 fallback materialization to helper bodies, while the program emitter
										 delegates wrapper/fnwrap compilation and program-data finalization; the
											 final capped profile moves the exposed body back to
											 `native_compile_program_x64` at about 880ms, leaving that remaining
											 orchestration body as the concrete parser target. Entry register-thread,
											 top/main entry calls, and platform return-path emission now live behind
											 small helper calls; the capped profile now exposes
											 `_emit_intrinsic_sys_linux_fs_x64` at about 770ms as the next x64 parser
											 body to split by syscall family. Linux FS intrinsic lowering now delegates
											 stat-family and path-family syscalls to helper bodies; the capped profile now
											 shows `x64_native_program.oren` at about 37.4s total / 27.4s parse, with
											 `_emit_eval_call_expr_to_rax` exposed at about 659ms as the next parser target.
											 X64 call-expression runtime/generic fast-path classification is now split out
											 of `_emit_eval_call_expr_to_rax`; the capped profile now shows
											 `x64_native_program.oren` at about 37.0s total / 27.2s parse, with
											 `_x64_collect_top_level_globals_and_stmts` exposed at about 606ms as the next
											 parser target. X64 top-level global collection now delegates runtime slot
											 reservation, user slot/fact preparation, and top-level initializer rewrite
											 into helper bodies; the capped profile now shows `x64_native_program.oren` at
											 about 37.7s total / 27.7s parse, with `_emit_ops_in_fn` exposed again at about
											 618ms as the next parser body. `_emit_ops_in_fn` now delegates `var_i32`,
											 `assign_i32`, and top-level string-init operation bodies to helpers, and Linux
											 x64 net intrinsic lowering delegates epoll-family syscalls to a helper; the
											 capped profile now shows `x64_native_program.oren` at about 37.2s total /
											 27.3s parse, with `_emit_intrinsic_sys_linux_misc_x64` exposed at about 557ms
											 as the next parser body. Linux x64 misc syscall lowering now delegates
											 fd-control syscalls (`fcntl`, `dup*`, `ioctl`, and related helpers) to a
											 helper body; the capped profile now shows `x64_native_program.oren` at about
											 37.4s total / 27.3s parse, with `_emit_eval_call_expr_to_rax` exposed again at
											 about 524ms as the next parser body. X64 call-expression lowering now delegates
												 scalar conversion/bool intrinsics to `_emit_eval_scalar_call_intrinsic_x64`;
												 the capped profile now shows `x64_native_program.oren` at about 37.4s total /
												 27.4s parse, with `native_compile_program_x64` exposed again at about 526ms
												 as the next parser body. `native_compile_program_x64` now delegates entry
												 prologue, stack scratch, and argv/env capture setup to
												 `_x64_emit_entry_prologue_and_args`; the capped profile now shows
												 `x64_native_program.oren` at about 37.0s total / 27.1s parse, with
												 `_emit_eval_infix_to_rax` exposed at about 470ms as the next parser body.
												 `_emit_eval_infix_to_rax` now delegates logical, comparison, modulo/division,
												 shift, bitwise, and integer arithmetic lowering to focused helpers in
												 `041_emit_infix_expr.oren`; the capped profile now shows
												 `x64_native_program.oren` at about 37.1s total / 27.4s parse, with
												 `_compile_function_v0` exposed at about 468ms as the next parser body.
												 `_compile_function_v0` now delegates frame/local/intrinsic-temp sizing to
												 `_x64_prepare_function_frame_v0`, and Linux x64 net syscall lowering now
												 delegates fd2/accept/sockopt/message families to helper bodies; the capped
												 profile now shows `x64_native_program.oren` at about 37.6s total / 27.8s
												 parse, with `native_compile_program_x64` exposed again at about 445ms as the
												 next parser body. `native_compile_program_x64` now delegates runtime-path/rtobj
												 choice and runtime/user statement preparation to helpers while preserving the
													 existing rtobj timing boundary; the capped profile now shows
													 `x64_native_program.oren` at about 37.8s total / 28.0s parse, with
													 `_x64_build_runtime_obj` exposed at about 435ms as the next parser body.
													 `_x64_build_runtime_obj` now delegates runtime function metadata collection,
													 local-function/lambda preparation, runtime/user splitting, and runtime-global
													 slot allocation to helper bodies while preserving the existing rtobj phase
														 markers; the capped profile now shows `x64_native_program.oren` at about
														 37.2s total / 27.5s parse, with `_emit_eval_call_expr_to_rax` exposed at
														 about 412ms as the next parser body. X64 pointer/memory/native-allocation
															 call intrinsics now live in `040_emit_call_intrinsics.oren`, and
															 `_emit_eval_call_expr_to_rax` delegates to compact classifier helpers after
															 scalar intrinsics; the capped profile now shows `x64_native_program.oren`
															 at about 37.1s total / 27.6s parse, with `_emit_fast_lcg_sum_while_x64`
															 exposed at about 409ms as the next parser body. X64 fast LCG sum and
															 list-int dot while emitters now delegate setup, repeated-step,
															 list-validation, and whole-list helper blocks to narrower helper bodies;
															 the capped profile now shows `x64_native_program.oren` at about 37.1s
															 total / 27.5s parse, with `_emit_eval_int_to_rax` exposed at about 390ms
															 as the next parser body. X64 expression evaluation now delegates literal,
															 singleton, lambda, intrinsic temp, and identifier value lowering to helper
															 bodies, and Linux x64 process syscalls delegate fork/exec/wait lowering
															 to a process-family helper; the capped profile now shows
															 `x64_native_program.oren` at about 37.3s total / 27.8s parse, with
															 `_x64_build_runtime_obj` exposed at about 355ms as the next parser body.
															 X64 runtime-object build now delegates runtime decl compilation, wrapper
															 synthesis/compilation, and top-decl reporting, and
																 `native_compile_program_x64` delegates function/global preparation to a
																 compact helper; the capped profile now shows `x64_native_program.oren` at
																 about 37.4s total / 27.8s parse, with `_emit_ops_in_fn` exposed at about
																 344ms as the next parser body. X64 op emission now delegates trace/progress,
																 phase-progress, dynamic-gas patching, slow-op recording, and remaining regular
																 dispatch helpers; entry runtime bootstrap now delegates heap/frame, boot-global,
																 argv/envp, runtime-init, static cstr/debug, args/envp, and capsule/GC setup to a
																	 bounded helper shard; and `_compile_function_v0` now delegates spills, call-depth
																	 gating, GC tick init, body emission, and epilogue emission. The capped profile
																	 now shows `x64_native_program.oren` at about 36.4s total / 27.2s parse, with
																	 `_emit_intrinsic_sys_linux_fd_misc_x64` exposed at about 312ms as the next parser
																	 body. Linux x64 fd-control syscall intrinsic lowering now delegates fcntl-family
																	 and dup/ioctl-family bodies to a dedicated include shard, and x64 user-global slot
																		 preparation now delegates alias-target collection, slow/progress tracing, and
																		 per-slot materialization to helpers. The capped profile now shows
																		 `x64_native_program.oren` at about 36.5s total / 27.6s parse, with
																		 `_emit_intrinsic_stack_helpers_x64` exposed at about 303ms as the next parser
																		 body. X64 stack/diagnostic intrinsics now delegate code-address, context-init,
																		 context-switch, and symbol-resolution lowering to focused helpers. The capped
																		 profile now shows `x64_native_program.oren` at about 36.7s total / 27.9s parse,
																		 with `_emit_intrinsic_sys_linux_x64` exposed at about 303ms as the next parser
																		 body. Linux x64 top-level syscall lowering now delegates Windows-compat ENOSYS
																		 stubs, getrandom/getentropy, and ulock/futex paths to focused helpers while
																		 preserving validation early returns. The capped profile now shows
																		 `x64_native_program.oren` at about 38.8s total / 29.8s parse, with
																		 `_emit_fast_list_int_get_sum_while_x64` exposed at about 311ms as the next
																		 parser body. X64 fast list-int get-sum while lowering now mirrors the dot
																		 fast-path split: preparation, list validation, optional whole-list helper,
																			 unrolled pair body, and single-step body are focused helpers. The capped
																			 profile now shows `x64_native_program.oren` at about 36.7s total / 27.7s
																			 parse, with `_emit_index_expr_v0` exposed at about 298ms as the next parser
																			 body. X64 index expression lowering now delegates operand spill/runtime fast
																				 paths, assumed-list indexing, receiver kind dispatch, and list/map emission
																				 to focused helpers. The capped profile now shows `x64_native_program.oren`
																				 at about 37.1s total / 28.1s parse, with
																				 `_emit_intrinsic_sys_linux_misc_x64` exposed at about 279ms as the next
																				 parser body. Linux x64 misc syscall lowering now delegates signal, time,
																				 cwd/scheduler/sleep, fd, and net families instead of keeping those cases in
																				 one parser body. The capped profile now shows `x64_native_program.oren` at
																				 about 36.8s total / 27.7s parse, with
																				 `_emit_fast_list_get_sum_while_x64` exposed at about 272ms as the next
																				 parser body. X64 fast list get-sum while lowering now mirrors the list-int
																				 split with preparation, sum-string flag, list-validation, and loop-body
																				 helpers. The capped profile now shows `x64_native_program.oren` at about
																				 37.9s total / 28.8s parse, with `native_compile_program_x64` exposed at
																				 about 285ms as the next parser body. `native_compile_program_x64` now
																				 delegates debug metadata setup, entry emission, function/backend tail
																				 compilation, and summary formatting to low-arity helpers. The capped
																				 profile now shows `x64_native_program.oren` at about 37.1s total / 27.8s
																				 parse, with `_emit_generic_call_expr_v0` exposed at about 267ms as the
																				 next parser body. X64 generic named-call lowering now delegates
																				 intrinsic/spread dispatch, callee classification, and direct ABI call
																				 emission to focused helpers; Linux stat-family syscall lowering now
																					 shares host-stat to `OrenStatV0` translation and splits `stat`/`lstat`
																					 from `fstat`. The capped profile now shows `x64_native_program.oren` at
																					 about 37.4s total / 28.3s parse, with `_emit_fast_lcg_sum_while_x64`
																					 exposed at about 268ms as the next parser body. X64 fast LCG sum while
																						 lowering now delegates entry gates, unsigned setup/loop, and signed
																						 full-mod loop emission to focused helpers. The capped profile now shows
																						 `x64_native_program.oren` at about 37.1s total / 28.0s parse, with
																						 `_emit_intrinsic_sys_linux_proc_x64` exposed at about 263ms as the next
																						 parser body. X64 Linux proc syscall lowering now delegates memory mapping
																						 and clone/thread families to helpers, and Linux FS syscall lowering now
																							 delegates runtime stubs, pipe, and open/close/access families to helpers.
																							 The capped profile now shows `x64_native_program.oren` at about 37.4s
																							 total / 28.2s parse, with `_emit_fast_list_int_push_while_x64` exposed at
																							 about 266ms as the next parser body. X64 fast list-int push while lowering
																							 now delegates preparation, list validation/reserve, loop stores, and final
																								 count updates to helper bodies. The capped profile now shows
																								 `x64_native_program.oren` at about 37.6s total / 28.3s parse, with
																								 `_emit_global_string_init_batch_op_x64` exposed at about 260ms as the next
																								 parser body. X64 fallback global string-batch lowering now delegates trace
																								 setup, legacy item collection, per-item string data append, table/loop
																								 emission, and slow-op reporting to helper bodies. The capped profile now
																								 shows `x64_native_program.oren` at about 37.4s total / 28.1s parse, with
																									 `_emit_intrinsic_sys_linux_path_family_x64` exposed at about 253ms as the
																									 next parser body. X64 Linux path-family syscall lowering now delegates
																									 unlink/rmdir, rename, mkdir/chmod, and getdirentries64 to helper bodies.
																										 The capped profile now shows `x64_native_program.oren` at about 37.0s
																										 total / 27.6s parse, with `_emit_fast_list_push_while_x64` exposed at
																										 about 242ms as the next parser body. X64 generic list-push and list-int
																										 dot fast-loop lowering now delegate preparation, validation, cursor setup,
																										 loop headers, unrolled pairs, single-step bodies, and count/fixup updates
																											 through helper bodies, while local label fixup helpers write label
																											 positions to the function label map. The capped profile now shows
																											 `x64_native_program.oren` at about 37.7s total / 28.3s parse, with
																											 `_emit_fast_list_dot_while_x64` exposed at about 244ms as the next parser
																											 body. X64 generic list-dot fast-loop lowering now delegates preparation,
																											 list validation, unique cursor setup, loop header, and single-step body
																												 emission through helper bodies. The capped profile now shows
																												 `x64_native_program.oren` at about 37.6s total / 28.2s parse, with
																												 `_x64_rtobj_apply_code_to_ctx` exposed at about 240ms as the next parser
																												 body. X64 runtime-object apply now delegates data-tail, globals/imports/FFI/cstr,
																												 function-metadata, code append, function-offset, compact-fixup, legacy-fixup,
																												 and rip-data32 merge phases to helper bodies; Windows CreateProcess syscall
																													 lowering now delegates preparation, spill/zeroing, create-call, wait, exit
																													 status, and cleanup emission. The capped profile now shows
																													 `x64_native_program.oren` at about 38.1s total / 28.6s parse, with
																													 `_x64_expr_is_floaty` exposed at about 217ms as the next parser body. X64
																													 float-return classification, Windows entry argv synthesis, and spawn
																													 expression lowering now delegate their large parser bodies into focused
																														 helper shards while preserving the same runtime helper boundaries. The
																														 capped profile now shows `x64_native_program.oren` at about 38.1s total /
																														 28.7s parse, with `_compile_function_v0` exposed at about 211ms as the next
																														 parser body. X64 function compilation now delegates phase setup, context
																														 reset, ops analysis logging, frame prologue emission, call-depth entry hook
																														 emission, and done-phase detail formatting; entry global-root emission now
																														 delegates skip filtering, traced name emission, vector/map collection,
																														 root-table loop emission, and phase logging. The capped profile now shows
																														 `x64_native_program.oren` at about 38.4s total / 28.7s parse, with
																														 `_emit_eval_pointer_call_intrinsic_x64` exposed at about 199ms as the next
																														 parser body. X64 pointer-call intrinsic lowering now delegates integer add,
																														 pointer loads, pointer stores, and unchecked u8-buffer loads to focused
																														 helpers; x64 `oren_index_set` lowering now delegates operand spilling, map
																														 calls, receiver-kind dispatch, and list/map path emission through helper
																														 bodies. The capped profile now shows `x64_native_program.oren` at about
																														 37.4s total / 28.0s parse, with `_emit_list_int_push_intrinsic_v0_x64`
																														 exposed at about 189ms as the next parser body. X64 `oren_list_int_push`
																														 lowering now delegates argument spilling, list-int validation, value/header
																														 preparation, slow/fast push paths, and optional list-header tracing through
																														 helper bodies. The capped profile now shows `x64_native_program.oren` at
																														 about 37.6s total / 28.0s parse, with `_x64_prepare_one_user_global_slot`
																														 exposed at about 188ms as the next parser body. X64 user-global slot
																														 preparation now delegates duplicate checks, direct `.data` initialization
																														 probes, fact collection, metadata registration, and slow-slot timing through
																														 helper bodies; `assign_i32` op lowering now delegates top-level string fast
																																 paths, empty-container fast paths, local/global facts, and global-slot
																																 stores. The capped profile now shows `x64_native_program.oren` at about
																																 37.6s total / 28.2s parse, with `_emit_intrinsic_sys_linux_net_x64` exposed
																																 at about 181ms as the next parser body. X64 Linux net syscall lowering now
																															 delegates socket and 3-argument address syscall families through focused
																																 helpers, making `_emit_intrinsic_sys_linux_net_x64` a router over the
																																 existing net helper bodies. The capped profile now shows
																																 `x64_native_program.oren` at about 37.2s total / 27.8s parse, with
																																 `_emit_intrinsic_sys_read_x64` exposed at about 176ms as the next parser body.
																																 X64 `sys_read` lowering now delegates Windows `ReadFile` and Linux syscall
																																 emission through platform-specific helpers after shared validation. The capped
																																 profile now shows `x64_native_program.oren` at about 37.3s total / 27.9s parse,
																																 with `_emit_list_push_intrinsic_v0_x64` exposed at about 176ms as the next
																																 parser body. X64 generic `oren_list_push` lowering now mirrors the list-int
																																	 helper layout, delegating argument spilling, validation, header reads,
																																	 slow/fast path emission, and optional header tracing through focused helpers.
																																	 The capped profile now shows `x64_native_program.oren` at about 38.0s total /
																																	 28.3s parse, with `_x64_build_runtime_obj` exposed at about 180ms as the next
																		 parser body. X64 runtime-object build orchestration now delegates final
																		 blob/meta materialization and summary printing through focused helpers. The
																		 capped profile now shows `x64_native_program.oren` at about 39.3s total /
																		 29.4s parse, with `_x64_build_top_level_init_stmts` exposed at about 190ms as
																		 the next parser body. X64 top-level initializer synthesis now delegates
																		 rewrite batch state, string literal batches, empty-container batches, Var
																		 rewrites, and progress logging through focused helpers. The capped profile
																		 now shows `x64_native_program.oren` at about 38.2s total / 28.6s parse, with
																		 `_emit_intrinsic_sys_stat_windows_x64` exposed at about 173ms as the next
																		 parser body. X64 Windows `sys_stat` / `sys_lstat` lowering now delegates
																		 OrenStatV0 zeroing, directory-success emission, file-open emission,
																		 file-success translation/close, and capsule post hooks through focused
																		 helpers. The capped profile now shows `x64_native_program.oren` at about
																		 38.5s total / 28.9s parse, with `_x64_emit_entry_return_path` exposed at about
																		 173ms as the next parser body. X64 entry return-path emission now delegates
																		 Windows DLL, Windows executable, Linux `.so`, and Linux executable return
																		 paths through focused helpers and shares heap-spill emission. The capped
																		 profile now shows `x64_native_program.oren` at about 38.3s total / 28.7s
																		 parse, with `_emit_intrinsic_sys_open_windows_x64` exposed at about 172ms as
																		 the next parser body. X64 Windows `sys_open` lowering now delegates capsule
																		 pre/post hooks, path normalization argument setup, desired-access mapping,
																		 creation-disposition stack args, and CreateFileA/error mapping through
																		 focused helpers. The capped profile now shows `x64_native_program.oren` at
																		 about 37.8s total / 28.3s parse, with
																		 `_emit_intrinsic_sys_linux_fcntl_x64` exposed at about 166ms as the next
																		 parser body. X64 Linux fd-control lowering now delegates raw `sys_fcntl`,
																		 `F_GETFL`, `F_SETFL`, and `getpath` fallback handling through focused helpers
																		 under the fd-misc router. The capped profile now shows
																		 `x64_native_program.oren` at about 38.2s total / 28.6s parse, with
																		 `_emit_intrinsic_sys_write_x64` exposed at about 167ms as the next parser
																		 body. X64 `sys_write` lowering now delegates Windows `WriteFile` and Linux
																		 syscall paths through platform-specific helper bodies while preserving
																		 capsule prehook and zero-length write behavior. The capped profile now
																		 shows `x64_native_program.oren` at about 38.1s total / 28.6s parse, with
																		 `_emit_malloc_size_in_rax` exposed at about 164ms as the next parser body.
																		 X64 malloc lowering now delegates 64KiB chunk sizing, Windows
																		 `VirtualAlloc`, Linux `mmap`, heap-register commit, fast bump allocation,
																		 and zero-size return through focused helpers while preserving the
																		 `malloc`/`malloc_raw`/`malloc_k` entry contract. The capped profile now
																		 shows `x64_native_program.oren` at about 37.9s total / 28.3s parse, with
																		 `_emit_intrinsic_sys_linux_open_close_access_x64` exposed at about 163ms as
																		 the next parser body. Linux x64 open/close/access lowering now delegates
																			 `sys_open`, `sys_close`, and `sys_access` through focused helpers under the
																			 FS router. The capped profile now shows `x64_native_program.oren` at about
																			 37.6s total / 28.1s parse, with `_x64_prepare_function_frame_v0` exposed at
																			 about 162ms as the next parser body. X64 function-frame preparation now
																			 delegates parameter slot/type inference, reserved scratch slots,
																				 intrinsic-temp sizing, literal spill slots, and ABI layout calculation to
																				 focused helpers while preserving the same frame map contract. The capped
																				 profile now shows `x64_native_program.oren` at about 38.2s total / 28.6s
																				 parse, with `_emit_intrinsic_sys_linux_ulock_x64` exposed at about 162ms as
																				 the next parser body. Linux x64 ulock/futex lowering now delegates shared
																					 futex syscall setup, timeout-timespec emission, timeout errno mapping,
																					 wait lowering, and wake lowering to focused helpers. The capped profile now
																					 shows `x64_native_program.oren` at about 40.1s total / 30.3s parse, with
																					 `_x64_program_compile_options` exposed at about 203ms as the next parser
																					 body. X64 program compile option parsing now delegates progress/focus, entry
																					 toggles, slow-function ranking, and phase-detail limits to focused helpers
																						 while preserving the returned option map. The capped profile now shows
																						 `x64_native_program.oren` at about 39.2s total / 29.5s parse, with
																						 `_emit_list_int_set_intrinsic_v0_x64` exposed at about 164ms as the next
																							 parser body. X64 `oren_list_int_set` lowering now delegates LTR argument
																							 spills, argument reloads, list-int validation, value/count checks, and
																							 slow/fast store emission through focused helper bodies. The capped profile
																							 now shows `x64_native_program.oren` at about 38.9s total / 29.1s parse, with
																							 `_emit_intrinsic_sys_getentropy_windows_x64` exposed at about 159ms as the
																							 next parser body. Windows x64 `sys_getentropy` lowering now delegates
																							 entropy data assets, argument spills, buffer/length guards, dynamic
																							 `bcrypt` resolution, RNG call emission, and finish/error mapping to focused
																							 helpers. The resolver reloads the cached-function-pointer slot address
																							 after WinAPI calls before storing the resolved pointer, avoiding reliance on
																							 volatile `r10`. The capped profile now shows
																							 `x64_native_program.oren` at about 37.7s total / 28.2s parse, with
																							 `_emit_stack_trace_best_effort` exposed at about 153ms as the next parser
																							 body. X64 best-effort panic stack-trace lowering now delegates Windows and
																							 Linux frame-walk/code-emission bodies to platform-specific helpers while
																							 keeping the shared scratch reservation wrapper small. The capped profile now
																							 shows `x64_native_program.oren` at about 38.0s total / 28.5s parse, with
																							 `_emit_list_len_intrinsic_v0_x64` exposed at about 179ms as the next parser
																							 body. X64 `oren_list_len` lowering now delegates argument validation/spilling,
																							 label setup, nil handling, untracked-list fallback, and tracked LIST/LIST_INT
																							 count emission to focused helper bodies while preserving the same panic and
																							 magic-check paths. The capped profile now shows
																							 `x64_native_program.oren` at about 39.8s total / 29.9s parse, with
																							 `_x64_compile_user_function_set` exposed at about 180ms as the next parser
																							 body. X64 user-function-set compilation now delegates option unpacking,
																							 per-function name/progress logging, detail toggling, slow-function live
																							 recording, and slow-summary emission to state-map helpers while preserving
																							 the low-arity loop call contract. The capped profile now shows
																							 `x64_native_program.oren` at about 39.5s total / 29.8s parse, with
																							 `_emit_ops_in_fn` exposed at about 164ms as the next parser body. X64
																							 function-op emission now delegates loop-state setup, gas-note charging,
																							 prebuilt top-level batch fast paths, post-op gas/slow logging, and body
																								 summary emission to focused helpers while preserving regular-op dispatch.
																								 The capped profile now shows `x64_native_program.oren` at about 38.3s total /
																								 28.6s parse, with `_emit_intrinsic_sys_linux_proc_clone_x64` exposed at about
																								 150ms as the next parser body. Linux x64 proc/clone lowering now delegates raw
																								 `sys_clone`, `sys_thread_create` state/spill setup, clone syscall setup, and
																								 child start/exit emission to focused helpers while preserving `sys_gettid`
																								 dispatch and the clone capsule prehook. The capped profile now shows
																								 `x64_native_program.oren` at about 38.3s total / 28.5s parse, with
																								 `_x64_emit_direct_named_call_v0` exposed at about 150ms as the next parser body.
																								 X64 direct named-call lowering now delegates explicit/default-`nil` argument
																								 spills, ABI register/stack loading, and call-fixup/FFI return normalization to
																								 focused helpers while leaving varargs on the fnobj ABI path. Linux x64 epoll
																								 lowering now delegates `sys_epoll_create1`, `sys_epoll_ctl`, and
																								 `sys_epoll_pwait` to syscall-family helpers. The capped profile now shows
																								 `x64_native_program.oren` at about 39.9s total / 29.9s parse, with
																								 `_emit_stack_trace_windows_best_effort` exposed at about 160ms as the next
																								 parser body. Windows x64 best-effort stack tracing now delegates frame guards,
																								 raw return-PC line formatting/writing, and frame-chain advance to focused
																								 helpers while the wrapper retains label/fixup ownership. The capped profile
																								 now shows `x64_native_program.oren` at about 38.9s total / 29.0s parse, with
																								 `_emit_intrinsic_sys_dispatch_x64` exposed at about 146ms as the next parser
																								 body. X64 syscall dispatch now keeps ABI-derived Windows target detection in
																								 a small helper and routes Windows syscalls through focused
																								 core/FS/time/entropy, net/IOCP/WinSock, and proc/thread/fcntl helper families
																								 before falling back to Linux lowering. The capped profile now shows
																								 `x64_native_program.oren` at about 38.7s total / 28.9s parse, with
																								 `_emit_intrinsic_sys_wsarecvfrom_windows_x64` exposed at about 147ms as the
																								 next parser body. Windows x64 `WSARecvFrom` lowering now delegates argument
																								 spill/state setup, capsule pre/post hooks, WSABUF/IAT call emission, and
																								 pending/error result normalization to focused helpers while preserving the
																								 same `WSA_IO_PENDING` success mapping. The capped profile now shows
																								 `x64_native_program.oren` at about 38.6s total / 28.8s parse, with
																								 `_emit_cmp_r64_r64_maybe_string_x64` exposed at about 178ms as the next parser
																								 body. X64 string-aware compare lowering now delegates spill-slot lookup,
																								 small-int fast path probes, string-pointer checks, inline strcmp lowering, and
																								 integer fallback emission to focused helpers, and runtime-object cache recovery
																								 now delegates cache identity, cache-hit apply, seed-hit apply, and store/apply
																								 finalization. The capped profile now shows `x64_native_program.oren` at about
																								 40.2s total / 30.3s parse, with `_emit_intrinsic_sys_linux_dup_ioctl_x64`
																								 exposed at about 152ms as the next parser body. Linux x64 dup/ioctl lowering
																								 now delegates raw `dup`, `dup2`/`dup3`, and `ioctl` syscall families to focused
																								 helpers while preserving capsule hook ordering and syscall register setup. The
																								 capped profile now shows `x64_native_program.oren` at about 39.7s total / 29.8s
																								 parse, with `_emit_intrinsic_sys_fstat_windows_x64` exposed at about 145ms as
																								 the next parser body. Windows x64 `sys_fstat` lowering now delegates fd/st
																								 argument spill and capsule prehook, standard-handle resolution, stat
																								 materialization, and capsule posthook emission to focused helpers while
																								 preserving best-effort zero-size success for non-file handles. The capped
																								 profile now shows `x64_native_program.oren` at about 39.3s total / 29.4s parse,
																								 with `_emit_list_int_get_intrinsic_v0_x64` exposed at about 142ms as the next
																								 parser body. X64 checked `oren_list_int_get` lowering now delegates argument
																								 spills, label setup, tracked LIST_INT validation, bounds checks, and element
																								 load emission to focused helpers while preserving the same panic strings and
																								 wrapper-owned fixup patching. The capped profile now shows
																								 `x64_native_program.oren` at about 39.1s total / 29.0s parse, with
																								 `_emit_intrinsic_sys_linux_windows_compat_x64` exposed at about 149ms as the
																								 next parser body. Linux x64 lowering for Windows-only compatibility intrinsics
																								 now shares ENOSYS validation/emission and delegates QPC, IOCP/cancel, and WSA
																									 families to focused helpers while preserving validation errors and handled
																									 return values. The capped profile now shows `x64_native_program.oren` at about
																									 39.0s total / 28.9s parse, with
																									 `_emit_eval_call_runtime_or_fast_generic_x64` exposed at about 135ms as the
																									 next parser body. X64 call fast-path classification now delegates
																									 runtime-required generic calls, internal-prefix generic calls, and typed-buffer
																									 runtime name detection to focused helpers; native-call intrinsic lowering
																										 delegates `native_call1`, allocator, and panic paths; list-int unchecked
																										 dot-slot lowering delegates validation/spill setup and loop-body emission. The
																										 capped profile now shows `x64_native_program.oren` at about 39.4s total /
																										 29.2s parse, with `_emit_intrinsic_sys_write_windows_x64` exposed at about
																										 133ms as the next parser body. Windows x64 `sys_write` lowering now delegates
																										 argument spill/prehook setup, standard-handle selection, and `WriteFile`
																										 result normalization to focused helpers. Missing fnwrap compilation delegates
																										 per-function synthesis/compile and phase logging, and the x64 SIMD dot
																											 intrinsic delegates argument setup, vector loop emission, and scalar tail
																											 emission. The capped profile now shows `x64_native_program.oren` at about
																											 39.3s total / 29.0s parse, with
																											 `_emit_intrinsic_sys_wsarecv_windows_x64` exposed at about 125ms as the next
																											 parser body. Windows x64 overlapped `WSARecv`/`WSASend` lowering now delegates
																											 state spilling, capsule pre/post hooks, IAT call setup, and pending/error
																											 normalization to focused helpers. Windows `getsockopt` lowering delegates
																											 spill state, capsule prehook, level/option translation, IAT call setup, and
																												 SO_ERROR normalization. The capped profile now shows
																												 `x64_native_program.oren` at about 41.2s total / 30.8s parse, with
																												 `_compile_function_v0` exposed at about 134ms as the next parser body.
																												 `_compile_function_v0` now delegates phase-state setup, function entry
																												 registration, phase timestamp marks, and body/epilogue emission; Windows
																												 x64 `sys_read` now delegates argument spill/prehook setup, handle
																												 selection, and `ReadFile` result normalization; debug metadata setup now
																												 delegates display labels, runtime-object symbol collection, and symtab
																													 reservation. The capped profile now shows `x64_native_program.oren` at
																													 about 40.0s total / 29.9s parse, with
																													 `_emit_intrinsic_sys_linux_cwd_sched_sleep_x64` exposed at about 121ms as
																													 the next parser body. Linux x64 cwd/scheduler/sleep syscall lowering now
																													 delegates `getcwd`, `sched_yield`, and `nanosleep` to focused helpers;
																													 Windows x64 `sys_gettimeofday` delegates argument spilling, capsule
																													 prehook, `tv` validation, wall-time materialization, and optional QPC
																													 emission; and checked x64 `oren_list_int_len` now mirrors the helperized
																														 `oren_list_len` validation shape. The capped profile now shows
																														 `x64_native_program.oren` at about 40.8s total / 30.6s parse, with
																														 `_emit_intrinsic_sys_linux_proc_exec_x64` exposed at about 120ms as the
																														 next parser body. Linux x64 process syscall lowering now delegates
																														 `fork`, `execve`, and `wait4` to focused helpers, and x64 context
																														 creation now delegates progress-trace detection, base map setup,
																														 alias/lambda state, runtime data-slot reservation, and debug trace flags.
															 The capped profile now shows `x64_native_program.oren` at about 40.4s
															 total / 30.1s parse, with `_emit_indirect_call_via_fnobj_x64` exposed
															 at about 120ms as the next parser body.
															 X64 indirect fn-object calls now delegate argument spilling, args-list
															 materialization, callee spilling, and wrapper-call emission; fast list-int
															 dot unroll2 lowering delegates per-multiply slot lookup, unrolled pair
															 emission, and loop-tail emission; and fast list-int push validation
															 delegates entry gates, reserve emission, and per-list validation. The
															 capped profile now shows `x64_native_program.oren` at about 40.3s total
															 / 30.0s parse, with `_emit_eval_scalar_call_intrinsic_x64` exposed at
															 about 118ms as the next parser body.
															 X64 scalar call intrinsics now delegate float bit-cast and
															 bool-normalization lowering, and fallback top-level string-batch data
															 append delegates progress tracing plus per-item offset/value/data
																 materialization. The capped profile now shows `x64_native_program.oren`
																 at about 40.3s total / 30.0s parse, with
																 `_x64_emit_ctx_switch_intrinsic` exposed at about 116ms as the next
																 parser body.
																 X64 context switching now delegates GPR save/restore,
																 resume-address capture, XMM save/restore, and next-context return
																 emission; Windows x64 path normalization delegates scratch setup,
																 local labels, copy loop, and finish patching; and Windows
																 `sys_setsockopt` mirrors the helperized `getsockopt` shape for
																 spill state, capsule prehook, WinSock constant translation, call
																 setup, and result normalization. The capped profile now shows
																 `x64_native_program.oren` at about 39.5s total / 29.2s parse, with
																 `_emit_intrinsic_sys_linux_net_addr3_x64` exposed at about 107ms as
																 the next parser body.
																 Linux x64 3-argument socket address syscalls now share addr3 helpers
																 for intrinsic state spilling, capsule prehooks, syscall-number
																 emission, and the connect/bind posthook paths while keeping
																 getpeername/getsockname as no-post syscalls. The capped profile now
																 shows `x64_native_program.oren` at about 39.6s total / 29.4s parse,
																 with `_x64_collect_top_level_globals_and_stmts` exposed at about
																 107ms as the next parser body.
																 X64 top-level global collection now delegates debug top-level
																 statement tracing, trace metadata formatting, slice-bound parsing,
																 slice tracing, and slice application while preserving the
																 `OREN_TRACE_TOP_LEVEL_*` and `OREN_TOP_LEVEL_*` debug environment
																 contracts. The capped profile now shows `x64_native_program.oren`
																 at about 39.8s total / 29.4s parse, with
																 `_x64_fast_list_push_validate_lists` exposed at about 107ms as the
																 next parser body.
																 X64 fast generic list-push validation now delegates loop-bound
																 checks, per-list temporary-slot state, list capture, tracked
																 LIST/magic validation, reserve emission, and count/buffer capture
																 to focused helpers. The capped profile now shows
																 `x64_native_program.oren` at about 40.0s total / 29.8s parse, with
																 `_x64_emit_entry_prologue_and_args` exposed at about 105ms as the
																 next parser body.
																 X64 entry prologue emission now delegates platform-kind detection,
																 DLL attach gating, Win64/SysV register preservation, executable
																 stack alignment, stack layout/reservation, prologue phase logging,
																 and Windows argv/env capture while preserving the returned entry
																 setup map. The capped profile now shows `x64_native_program.oren`
																 at about 40.2s total / 29.7s parse, with
																 `_x64_emit_ffi_stub_linux_dyn` exposed at about 104ms as the next
																 parser body.
																 Linux x64 dynamic FFI stubs now delegate data-cell/string
																 materialization, cached function-pointer load, SysV argument
																 spill/restore, resolver call, cache-store, target tailcall, and
																 unresolved-symbol panic emission while preserving local fixup
																 ownership. The capped profile now shows `x64_native_program.oren`
																 at about 40.8s total / 29.8s parse, with
																 `_emit_varargs_named_call_via_fnobj_x64` exposed at about 117ms as
																 the next parser body.
																 X64 varargs named-call lowering now delegates state preparation,
																 left-to-right explicit argument spills, spill-slot preparation,
																 argument-list allocation, ordered list pushes, named fn-object
																 spilling, and inline `oren_call_obj_list` emission to focused
																	 helpers. The capped profile now shows `x64_native_program.oren` at
																	 about 40.9s total / 30.1s parse, with
																	 `_emit_fast_list_int_get_sum_while_x64` exposed at about 134ms as the
																	 next parser body.
																	 X64 fast list-int get-sum while lowering now delegates label setup,
																	 bounds checks, optional whole-list helper dispatch, loop header/unroll
																	 guarding, loop-body emission, and final jump fixup resolution to
																	 focused helpers. The capped profile now shows
																	 `x64_native_program.oren` at about 40.6s total / 30.1s parse, with
																	 `_emit_intrinsic_sys_linux_proc_memory_x64` exposed at about 104ms as
																	 the next parser body.
																	 X64 Linux proc-memory syscall lowering now delegates private anonymous
																	 mmap and munmap emission to focused helpers with a shared ABI-kind
																	 probe while preserving capsule hook argument registers and Windows
																	 fallback emission. The capped profile now shows
																	 `x64_native_program.oren` at about 41.3s total / 30.9s parse, with
																	 `_emit_intrinsic_sys_linux_access_x64` exposed at about 130ms as the
																	 next parser body.
																	 X64 Linux `sys_access` lowering now delegates argument spill state,
																	 capsule prehook pair handling, `faccessat` syscall register setup, and
																	 capsule posthook emission to focused helpers under the FS router. The
																	 capped profile now shows `x64_native_program.oren` at about 43.0s
																	 total / 32.3s parse, with `_x64_fast_list_get_sum_emit_single` exposed
																	 at about 112ms as the next parser body.
																	 X64 generic list get-sum single-step lowering now delegates list-index
																	 resolution, element load emission, and integer/string-aware accumulation
																	 to focused helpers while preserving the fast-loop sum and index
																	 writeback contract. The capped profile now shows
																	 `x64_native_program.oren` at about 40.7s total / 30.1s parse, with
																	 `_x64_compile_program_function_sequence` exposed at about 221ms as the
																	 next parser body.
																	 X64 program function-sequence orchestration now delegates top-level/rtobj
																	 setup, user-function loop option packing, and wrapper/fnwrap/FFI/panic
																	 tail emission to focused helpers while preserving the phase timing map
																	 returned to the compile summary. The capped profile now shows
																	 `x64_native_program.oren` at about 41.7s total / 31.0s parse, with
																	 `_x64_emit_ffi_stub_win64` exposed at about 105ms as the next parser body.
																	 Win64 x64 dynamic FFI stubs now delegate data materialization, cached
																	 fnptr load, shadow-space argument spill/restore, resolver call,
																	 cache-store, target tailcall, and unresolved-symbol panic emission to
																	 focused helpers. The capped profile now shows
																	 `x64_native_program.oren` at about 40.7s total / 30.1s parse, with
																	 `_x64_emit_regular_op` exposed at about 101ms as the next parser body.
																	 X64 regular op dispatch now delegates straight-line declaration/
																	 expression/print/return ops and control-flow/loop ops to focused routers
																	 while preserving the existing `0`/`1` status contract for gas patching
																	 and fast-path skips. The capped profile now shows
																	 `x64_native_program.oren` at about 41.3s total / 30.5s parse, with
																	 `_x64_emit_entry_top_and_main_calls` exposed at about 116ms as the next
																	 parser body.
																	 X64 entry top/main call emission now delegates top-level call/skip
																	 tracing and executable main-or-zero return setup to focused helpers while
																		 preserving DLL/SO no-main behavior and phase-log fixup counters. The
																		 capped profile now shows `x64_native_program.oren` at about 42.6s total
																		 / 31.6s parse, with `_data_finalize_cstr0_table` exposed at about 140ms
																		 as the next parser body.
																		 X64 C-string static-table finalization now delegates reserved-slot
																		 decoding, runtime-object offset counting/appending, user literal offset
																		 appending, and slot patching to focused helpers while preserving the
																		 PIE-safe table layout. The capped profile now shows
																		 `x64_native_program.oren` at about 40.7s total / 30.1s parse, with
																		 `_emit_eval_prefix_to_rax` exposed at about 100ms as the next parser
																		 body.
																		 X64 prefix expression lowering now delegates boolean singleton mapping,
																		 language-truthiness `!`, compare-infix `!`, and float/integer negation
																		 to focused helpers while preserving runtime singleton and IEEE sign-bit
																		 semantics. The capped profile now shows `x64_native_program.oren` at
																		 about 40.6s total / 30.1s parse, with
																		 `_emit_intrinsic_sys_get_queued_completion_status_ex_windows_x64`
																		 exposed at about 96ms as the next parser body.
																		 Windows x64 `sys_get_queued_completion_status_ex` lowering now delegates
																		 six-argument spill state, Win64 stack-argument call setup, and
																		 GetLastError normalization to focused helpers while preserving timeout,
																		 invalid-parameter, invalid-handle, and default EIO mappings. The capped
																		 profile now shows `x64_native_program.oren` at about 40.8s total /
																		 30.1s parse, with `_data_finalize_dbginfo_table` exposed at about 97ms
																		 as the next parser body.
																		 X64 debug-info table finalization now delegates debug-build slot gating,
																		 function-entry collection/sorting, per-entry emission, display-name
																		 lookup, and reserved-slot patching to focused helpers while preserving
																		 the runtime symbolication table layout. The capped profile now shows
																		 `x64_native_program.oren` at about 42.8s total / 32.0s parse, with
																		 `_x64_fast_lcg_emit_fullmod_loop` exposed at about 108ms as the next
																		 parser body.
																		 X64 fast LCG sum full-mod fallback now delegates loop condition,
																		 throttled safepoint, state reload, signed full-mod step, and
																		 writeback/increment to focused helpers while preserving signed `idiv`
																		 modulo behavior. The capped profile now shows
																		 `x64_native_program.oren` at about 41.2s total / 30.6s parse, with
																		 `_emit_float_cmp_to_bool_x64` exposed at about 99ms as the next parser
																		 body.
																		 X64 float comparison lowering now delegates operand spilling, XMM
																		 load/convert, ordered/unordered condition dispatch, and bool result
																		 patching to focused helpers while preserving IEEE NaN behavior for each
																		 relation. The capped profile now shows `x64_native_program.oren` at
																		 about 40.8s total / 29.9s parse, with `_emit_malloc_size_in_rax`
																		 exposed at about 141ms as the next parser body.
																		 X64 malloc core lowering now delegates `$tmp0` validation, allocation
																		 labels, size alignment, native reuse probing, heap fast-path probing,
																		 and platform slow-path routing to focused helpers while preserving heap
																			 register semantics. The capped profile now shows
																			 `x64_native_program.oren` at about 40.6s total / 30.0s parse, with
																			 `_emit_call_spread_via_runtime_helper_fnexpr_x64` exposed at about 96ms
																			 as the next parser body.
																			 X64 spread-call lowering now delegates spill layout, left-to-right
																			 explicit argument spilling, fixed-list construction, spread/callee
																			 spilling, and `oren_call_obj_spread` emission to focused helpers while
																			 preserving injected runtime gating and temp cleanup on failure. The
																				 capped profile now shows `x64_native_program.oren` at about 43.0s
																				 total / 31.8s parse, with
																				 `_emit_wsa_last_error_to_neg_errno_common_x64` exposed at about 124ms
																				 as the next parser body.
																				 X64 Windows WSA error normalization now shares the repeated
																				 compare/set/jump case emission between common socket-error and
																				 connect-specialized mappings while preserving POSIX errno
																					 translations and local fixup ownership. The capped profile now shows
																					 `x64_native_program.oren` at about 41.5s total / 30.5s parse, with
																					 `_x64_emit_resolve_symbol_intrinsic` exposed at about 95ms as the next
																					 parser body.
																					 X64 `resolve_symbol` intrinsic lowering now delegates default
																					 `"???"` materialization, symtab offset decoding, range setup, and
																					 range-table loop emission to focused helpers while preserving embedded
																						 debug-symbol fallback semantics. The capped profile now shows
																						 `x64_native_program.oren` at about 41.1s total / 30.3s parse, with
																						 `_emit_intrinsic_sys_ulock_wait_windows_x64` exposed at about 94ms as
																						 the next parser body.
																						 X64 Windows `sys_ulock_wait` lowering now delegates temp setup,
																						 argument spilling, timeout-us to timeout-ms conversion,
																						 `WaitOnAddress` call setup, and result/timeout errno mapping to
																							 focused helpers while preserving temp cleanup ownership. The capped
																							 profile now shows `x64_native_program.oren` at about 41.4s total /
																							 30.6s parse, with `_emit_cmp_from_cond` exposed at about 96ms as the
																							 next parser body.
																							 X64 condition compare lowering now delegates integer,
																							 identifier/global, and general-expression RHS paths plus
																							 truthy/prefix fallback into focused helpers while preserving
																								 string-aware compare routing. The capped profile now shows
																								 `x64_native_program.oren` at about 41.6s total / 30.7s parse, with
																								 `_x64_index_emit_kind_dispatch` exposed at about 99ms as the next
																								 parser body.
																								 X64 index receiver kind dispatch now delegates tracked lookup,
																								 tracked guards, node-kind loading, and known list/list-int/map plus
																								 dynamic receiver branches to focused helpers while preserving panic
																									 messages and list/map branch labels. The capped profile now shows
																									 `x64_native_program.oren` at about 41.4s total / 30.6s parse, with
																									 `_emit_list_int_get_unchecked_intrinsic_v0_x64` exposed at about
																									 95ms as the next parser body.
																									 X64 unchecked list-int get lowering now reuses the checked get
																									 argument-spill helper and delegates unchecked labels, nil
																									 validation, bounds checks, and final value load to focused helpers
																									 while preserving unchecked header semantics. The capped profile now
																									 shows `x64_native_program.oren` at about 41.1s total / 30.2s parse,
																									 with `_x64_build_runtime_obj` exposed at about 93ms as the next
																									 parser body.
																									 X64 runtime-object build orchestration now delegates trace/timing
																									 setup, runtime parse/context setup, runtime input preparation,
																									 decl/wrapper compilation, and final result packaging to focused
																									 helpers. X64 false-branch condition lowering now delegates float
																									 compare, prefix-`!` float compare, prefix-`!` truthiness, and plain
																									 truthy-expression branches while preserving integer compare fallback.
																									 The capped profile now shows `x64_native_program.oren` at about
																									 41.3s total / 30.6s parse, with
																									 `_emit_resolve_symbol_ptr_and_off_best_effort` exposed at about
																									 93ms as the next parser body.
																									 X64 best-effort symbol pointer/offset resolution now delegates
																									 default `"???"` materialization, symtab offset decoding, fixed-base
																									 symtab setup, and scan/match emission to focused helpers.
																									 Runtime-object global metadata apply now delegates root metadata
																									 extraction, whole-map adoption, root progress logging, per-global
																										 fallback merge, and final adopted/count logging. The capped profile
																										 now shows `x64_native_program.oren` at about 40.8s total / 30.1s
																										 parse, with `_x64_emit_list_int_dot_slots_unchecked_body` exposed
																										 at about 92ms as the next parser body.
																										 X64 unchecked list-int dot-slots lowering now delegates label/fixup
																										 state, nil/length checks, pointer setup, and loop emission to focused
																										 helpers. The fast list-int dot single-step loop now reuses the
																										 mul-slot resolver and delegates unique cursor reads, indexed reads,
																										 and tail writeback. The capped profile now shows
																											 `x64_native_program.oren` at about 40.8s total / 30.0s parse, with
																											 `_x64_match_fast_lcg_sum_while` exposed at about 87ms as the next
																											 parser body.
																											 X64 fast LCG sum-while matching now delegates condition/local-int
																											 gates, body-shape extraction, LCG/mod validation, and accumulator
																											 validation to focused helpers. X64 program function-set preparation
																											 now delegates local-fn rewrites, function/type-constructor
																											 collection, FFI/top-level global collection, callable-use scanning,
																											 and wrapper prep. Unchecked list-int reduce-sum slots lowering now
																											 delegates argument preparation, label state, nil/setup, loop
																											 emission, and finish/patching. The capped profile now shows
																											 `x64_native_program.oren` at about 41.5s total / 30.7s parse, with
																											 `_emit_intrinsic_sys_linux_net_msg_x64` exposed at about 85ms as the
																											 next parser body.
																											 Linux x64 `sendto`/`recvfrom` message syscall lowering now delegates
																											 syscall name matching, six-argument spill state, capsule prehook
																											 argument loading, syscall argument loading, and syscall-number emission
																											 to focused helpers. Lambda literal lowering now delegates metadata/
																											 capture registration, env spill allocation, capture-env materialization,
																											 and `oren_func` object construction. The capped profile now shows
																												 `x64_native_program.oren` at about 41.8s total / 30.8s parse, with
																												 `_emit_intrinsic_sys_stat_windows_x64` exposed at about 83ms as the next
																												 parser body.
																												 Windows x64 `sys_stat` / `sys_lstat` lowering now delegates argument
																												 spilling, capsule prehook path resolution, label/fixup setup, path
																												 normalization plus attribute probing, directory/file dispatch, and final
																													 patch/posthook cleanup. The capped profile now shows
																													 `x64_native_program.oren` at about 41.9s total / 31.0s parse, with
																													 `_x64_expr_is_inty` exposed at about 84ms as the next parser body.
																													 X64 integer-expression classification now delegates identifier fact lookup,
																													 prefix recursion, integer infix recursion, list-int index recognition, and
																													 integer-returning call-name groups to focused helpers while preserving the
																													 float-exclusion gate. The capped profile now shows
																													 `x64_native_program.oren` at about 41.6s total / 30.7s parse, with
																													 `_emit_intrinsic_sys_linux_time_x64` exposed at about 82ms as the next
																													 parser body.
																													 Linux x64 `sys_gettimeofday` lowering now delegates temp-state setup,
																													 argument spills, capsule prehook emission, raw `gettimeofday`, and optional
																													 monotonic `clock_gettime` synthesis to focused helpers while preserving the
																														 stable 3-argument runtime ABI. The capped profile now shows
																														 `x64_native_program.oren` at about 41.0s total / 30.2s parse, with
																														 `_emit_print_stmt_str_x64` exposed at about 81ms as the next parser body.
																														 X64 print-string statement lowering now delegates expression evaluation,
																														 string-length materialization, reusable `sys_write` temp setup, write-arg
																														 storage, and newline literal emission to focused helpers while keeping the
																														 shared Linux/Windows `sys_write` path. The capped profile now shows
																														 `x64_native_program.oren` at about 42.2s total / 31.3s parse, with
																														 `_emit_intrinsic_sys_fcntl_setfl_windows_x64` exposed at about 82ms as
																														 the next parser body.
																														 Windows x64 `sys_fcntl_setfl` lowering now delegates temp-state setup,
																														 capsule pre/post hooks, nonblocking `FIONBIO` mode materialization,
																														 `ioctlsocket`, and WSA errno normalization to focused helpers. The capped
																														 profile now shows `x64_native_program.oren` at about 42.2s total / 31.3s
																														 parse, with `_emit_intrinsic_sys_mkdir_or_chmod_windows_x64` exposed at
																														 about 82ms as the next parser body.
																														 Windows x64 `sys_mkdir` / `sys_chmod` lowering now delegates temp-state
																														 setup, capsule path resolution, CreateDirectory/no-op chmod operation
																														 emission, BOOL-to-errno normalization, and capsule posthooks to focused
																															 helpers. The capped profile now shows `x64_native_program.oren` at about
																															 41.8s total / 30.6s parse, with
																															 `_emit_intrinsic_sys_win_wait_single_object_windows_x64` exposed at about
																															 81ms as the next parser body.
																															 Windows x64 `sys_win_wait_single_object` lowering now delegates temp-state
																															 setup, timeout-to-INFINITE argument normalization, the `WaitForSingleObject`
																															 IAT call, and WAIT-code result mapping to focused helpers while preserving
																															 the `0` / `-ETIMEDOUT` / `-1` contract. The capped profile now shows
																															 `x64_native_program.oren` at about 41.7s total / 30.5s parse, with
																															 `_emit_intrinsic_sys_sendto_windows_x64` exposed at about 79ms as the next
																															 parser body.
																															 Windows x64 `sys_sendto` / `sys_recvfrom` lowering now shares six-argument
																															 socket message helpers for temp-state setup, Win64 stack-arg loading,
																															 capsule prehooks, IAT dispatch, and WSA errno normalization. The capped
																																 profile now shows `x64_native_program.oren` at about 42.4s total / 31.4s
																																 parse, with `_x64_fast_list_dot_emit_single` exposed at about 82ms as the
																																 next parser body.
																																 Generic x64 LIST dot fast-loop single-step lowering now mirrors the LIST_INT
																																 split shape with focused helpers for multiplication slot resolution,
																																	 unique-cursor reads, indexed reads, multiply/add emission, and tail writeback.
																																	 The capped profile now shows `x64_native_program.oren` at about 41.2s total /
																																	 30.3s parse, with `_emit_eval_call_expr_to_rax` exposed at about 79ms as the
																																	 next parser body.
																																	 X64 expression lowering now splits call target normalization, zero-arg GC
																																	 calls, `oren_` prefix classification, intrinsic/syscall routing, shift
																																	 count lowering, and LIST_INT get-sum validation substeps into focused helpers.
																																		 The capped profile now shows `x64_native_program.oren` at about 42.4s total /
																																		 31.1s parse, with `_x64_fast_list_dot_validate_lists` exposed at about 80ms
																																		 as the next parser body.
																																		 X64 LIST/LIST_INT dot fast-loop lowering now splits generic LIST validation
																																		 into slot-state, capture, header, count, and buffer helpers, and keeps the
																																		 LIST_INT dot wrapper as validation/helper, loop-core, and finish/slow-path
																																			 orchestration helpers. The capped profile now shows `x64_native_program.oren`
																																			 at about 43.6s total / 32.3s parse, with
																																			 `_emit_win32_last_error_to_neg_errno_common_x64` exposed at about 83ms as the
																																			 next parser body.
																																			 Windows x64 Win32 `GetLastError` errno lowering now shares the repeated
																																			 compare/set/jump case emission through `_emit_win32_neg_errno_case_x64` while
																																			 preserving the POSIX-style ENOENT, EACCES, EBADF, EBUSY, EEXIST, ENOTEMPTY,
																																				 EXDEV, and fallback EIO mappings. The capped profile now shows
																																				 `x64_native_program.oren` at about 41.4s total / 30.5s parse, with
																																				 `_emit_intrinsic_sys_rename_windows_x64` exposed at about 79ms as the next
																																				 parser body.
																																				 Windows x64 `sys_rename` lowering now mirrors the adjacent mkdir/chmod helper
																																				 shape with focused state/eval, capsule prehook, `MoveFileExA`, BOOL-result,
																																				 and capsule posthook helpers while preserving path normalization and
																																					 replace-existing semantics. The capped profile now shows
																																					 `x64_native_program.oren` at about 41.5s total / 30.7s parse, with
																																					 `_emit_resolve_loc_ptr_best_effort` exposed at about 85ms as the next parser
																																					 body.
																																					 X64 best-effort panic location resolution now mirrors the symbol resolver with
																																					 focused default-location, linetab setup, and scan-loop helpers while preserving
																																						 debug-only linetab fallback and unsigned fixed-base address checks. The capped
																																						 profile now shows `x64_native_program.oren` at about 41.7s total / 30.7s parse,
																																						 with `_emit_infix_add_or_string_concat_x64` exposed at about 78ms as the next
																																						 parser body.
																																						 X64 infix `+` lowering now keeps the wrapper as a small router and delegates
																																						 known-int direct add and injected-runtime `oren_add` fallback emission to
																																							 focused helpers while preserving the handled/nil contract used by infix
																																							 dispatch. The capped profile now shows `x64_native_program.oren` at about
																																							 42.1s total / 31.1s parse, with `_x64_collect_callable_uses` exposed at about
																																							 79ms as the next parser body.
																																							 X64 callable-use collection now separates lambda scanning/phase logging,
																																							 optional `OREN_DEBUG_X64_LAMBDAS` reporting, and named function value-use
																																								 discovery while preserving the same statement-set return and wrapper
																																								 preparation contract. The capped profile now shows `x64_native_program.oren`
																																								 at about 42.8s total / 31.7s parse, with `_x64_rtobj_apply_function_offsets`
																																								 exposed at about 80ms as the next parser body.
																																								 X64 runtime-object function-offset replay now routes compact sidecar
																																								 attachment and legacy map replay through focused helpers while preserving
																																									 call-depth hook discovery, base-code adjustment, and phase-log path reporting.
																																									 The capped profile now shows `x64_native_program.oren` at about 41.6s total /
																																									 30.7s parse, with `_emit_intrinsic_sys_linux_net_sockopt_x64` exposed at about
																																									 77ms as the next parser body.
																																									 Linux x64 `sys_getsockopt` / `sys_setsockopt` lowering now mirrors the
																																									 adjacent Linux net-message helper shape with shared spill state, capsule
																																									 prehook argument loading, syscall argument loading, and syscall-number
																																										 dispatch helpers. The capped profile now shows `x64_native_program.oren` at
																																										 about 42.1s total / 31.1s parse, with
																																										 `_emit_intrinsic_sys_nanosleep_windows_x64` exposed at about 78ms as the next
																																										 parser body.
																																										 Windows x64 `sys_nanosleep` lowering now delegates temp/eval setup, capsule
																																										 prehook adjustment, nonpositive fast return, nanosecond-to-DWORD millisecond
																																										 conversion, and `Sleep` call/result emission to focused helpers while
																																										 preserving the best-effort no-EINTR contract. The capped profile now shows
																																										 `x64_native_program.oren` at about 42.9s total / 31.8s parse, with
																																										 `_x64_emit_sys_stat_or_lstat_x64` exposed at about 77ms as the next parser
																																										 body.
																																										 Linux x64 `sys_stat` / `sys_lstat` lowering now delegates temp layout,
																																										 capsule path resolution, host-stat buffer offset derivation, `newfstatat`
																																										 setup, and capsule posthook emission to focused helpers while preserving the
																																										 38-qword spill-gap layout that prevents kernel `struct stat` writes from
																																										 clobbering spilled args. The capped profile now shows
																																										 `x64_native_program.oren` at about 42.6s total / 31.5s parse, with
																																										 `_x64_fast_list_int_push_validate_one_list` exposed at about 77ms as the next
																																										 parser body.
																																										 X64 fast LIST_INT push validation now mirrors the generic LIST push helper
																																										 shape with separate list-state capture, nil/list capture, tracked LIST_INT
																																										 validation, reserve/count check, and buffer-slot capture helpers. The capped
																																										 profile now shows `x64_native_program.oren` at about 41.8s total / 30.7s
																																										 parse, with `_emit_intrinsic_sys_linux_pipe_x64` exposed at about 74ms as the
																																										 next parser body.
																																										 Linux x64 `sys_pipe` lowering now delegates pointer/rc spill setup, capsule
																																										 prehook, `pipe2` syscall setup, success-only int[2]-to-u64 fd widening, and
																																										 capsule posthook emission to focused helpers while preserving the saved-rc
																																											 RAX contract. The capped profile now shows `x64_native_program.oren` at about
																																											 42.0s total / 30.9s parse, with `_x64_match_fast_list_int_dot_while` exposed
																																											 at about 75ms as the next parser body.
																																											 X64 fast LIST_INT/LIST dot-while matching now shares counted-loop validation,
																																											 typed/generic dot step dispatch, and dot-body accumulation helpers while
																																												 keeping the public matcher entrypoints tiny. The capped profile now shows
																																												 `x64_native_program.oren` at about 43.0s total / 31.6s parse, with
																																												 `_x64_extract_type_constructors_v0` exposed at about 80ms as the next parser
																																												 body.
																																												 X64 synthesized type-constructor extraction now delegates linked-statement
																																												 access, type-name validation, field parameter/hash shaping, function synthesis,
																																												 and context registration to focused helpers while preserving function arity and
																																													 declaration-order side effects. The capped profile now shows
																																													 `x64_native_program.oren` at about 42.1s total / 30.9s parse, with
																																													 `_emit_fast_list_get_sum_while_x64` exposed at about 79ms as the next parser
																																													 body.
																																													 X64 fast LIST get-sum loop lowering now delegates label setup, entry gates,
																																													 validation fallback, loop condition/body emission, and finish/slow-path
																																														 orchestration to focused helpers while preserving the generic slow fallback.
																																														 The capped profile now shows `x64_native_program.oren` at about 42.4s total /
																																														 31.3s parse, with `_x64_ulock_wait_emit_result_windows` exposed at about
																																														 84ms as the next parser body.
																																														 Windows x64 `sys_ulock_wait` result mapping now delegates label/fixup state,
																																														 BOOL dispatch, `GetLastError` timeout dispatch, and success/timeout/failure
																																														 return emission to focused helpers while preserving the `0` / `-ETIMEDOUT` /
																																															 `-EIO` contract. The capped profile now shows `x64_native_program.oren` at
																																															 about 42.9s total / 31.6s parse, with
																																															 `_x64_fast_list_get_sum_validate_lists` exposed at about 76ms as the next
																																															 parser body.
																																															 X64 fast LIST get-sum validation now delegates per-list temp state, list
																																															 capture, tracked LIST kind validation, magic/count checks, and buffer capture
																																															 to focused helpers while preserving slow-path jumps and temp cleanup on setup
																																																 failure. The capped profile now shows `x64_native_program.oren` at about
																																																 42.1s total / 31.1s parse, with
																																																 `_emit_intrinsic_sys_post_queued_completion_status_windows_x64` exposed at
																																																 about 74ms as the next parser body.
																																																 Windows x64 `sys_post_queued_completion_status` lowering now delegates
																																																 argument spill state, `PostQueuedCompletionStatus` call setup, BOOL dispatch,
																																																 Win32 error mapping, success emission, and temp cleanup to focused helpers
																																																	 while preserving the `0` / `-EINVAL` / `-EBADF` / `-EIO` contract. The capped
																																																	 profile now shows `x64_native_program.oren` at about 43.4s total / 32.1s
																																																	 parse, with `_x64_fast_list_int_dot_validate_lists` exposed at about 78ms as
																																																	 the next parser body.
																																																	 X64 fast LIST_INT dot validation now delegates per-list temp state, list
																																																	 capture, tracked LIST_INT kind validation, magic/count checks, and buffer
																																																		 capture to focused helpers while preserving slow-path jumps and temp cleanup
																																																		 on setup/compiler failure. The capped profile now shows
																																																		 `x64_native_program.oren` at about 45.0s total / 33.5s parse, with
																																																		 `_x64_emit_compiled_function_body` exposed at about 81ms as the next parser
																																																		 body.
																																																		 X64 compiled function-body orchestration now delegates runtime entry setup,
																																																		 body-op emission, done-phase detail packing, and epilogue/reporting to
																																																		 focused helpers while preserving call-depth, GC tick, phase-log, and trace
																																																			 ordering. The capped profile now shows `x64_native_program.oren` at about
																																																			 42.3s total / 30.9s parse, with
																																																			 `_emit_intrinsic_sys_unlink_or_rmdir_windows_x64` exposed at about 73ms as
																																																			 the next parser body.
																																																			 Windows x64 `sys_unlink` / `sys_rmdir` lowering now delegates temp path
																																																			 state, capsule prehook, DeleteFile/RemoveDirectory dispatch,
																																																			 BOOL-to-errno mapping, and capsule posthook to focused helpers while
																																																				 preserving the resolved-path pair and rc posthook ordering. The capped
																																																				 profile now shows `x64_native_program.oren` at about 42.6s total / 31.4s
																																																				 parse, with `_emit_eval_call_internal_fast_generic_x64` exposed at about
																																																				 74ms as the next parser body.
																																																				 X64 internal fast-call routing now delegates generic-call emission,
																																																				 fixed-width prefix checks, `insn_`/`push_`, `set_`/`bytes_`, and
																																																				 `native_` handling to focused helpers while preserving the `native_call1`
																																																					 intrinsic escape hatch. The capped profile now shows
																																																					 `x64_native_program.oren` at about 42.5s total / 31.2s parse, with
																																																					 `_x64_fast_lcg_emit_unsigned_loop` exposed at about 76ms as the next parser
																																																					 body.
																																																					 X64 fast LCG unsigned loop emission now mirrors the fullmod helper shape by
																																																					 delegating condition, throttled safepoint, unroll2 body,
																																																					 single-iteration tail, and final writeback/exit emission to focused helpers.
																																																						 The capped profile now shows `x64_native_program.oren` at about 43.1s total
																																																						 / 31.6s parse, with `_x64_match_fast_list_int_get_sum_while` exposed at
																																																						 about 74ms as the next parser body.
																																																						 X64 counted fast-loop matching now shares one integer counted-loop recognizer
																																																						 across LIST_INT get-sum, generic LIST get-sum, and dot-product matchers, with
																																																							 LIST_INT/LIST get-sum accumulation split into focused helpers. The capped
																																																							 profile now shows `x64_native_program.oren` at about 42.6s total / 31.1s
																																																							 parse, with `_x64_emit_assign_top_string_fast` exposed at about 76ms as the
																																																							 next parser body.
																																																							 X64 top-level string assignment now shares one literal-store path between
																																																							 direct global-string init and assign-fast lowering, including global offset
																																																							 resolution, C-string table append timing, global-store emission, and slow-op
																																																								 phase logging. The capped profile now shows `x64_native_program.oren` at
																																																								 about 42.3s total / 31.0s parse, with `_emit_hash_literal_expr` exposed at
																																																								 about 72ms as the next parser body.
																																																								 X64 list/hash literal lowering now shares cached literal-temp lookup,
																																																								 constructor allocation, depth cleanup, and error checks; hash literal insertion
																																																								 delegates pair validation and key-kind annotated map-set emission to focused
																																																								 helpers while preserving deterministic integer/string key lowering. The capped
																																																								 profile now shows `x64_native_program.oren` at about 42.3s total / 31.0s
																																																								 parse, with `_x64_emit_sys_mkdir_or_chmod_x64` exposed at about 72ms as the
																																																								 next parser body.
																																																								 Linux x64 `sys_mkdir` / `sys_chmod` lowering now mirrors the platform FS helper
																																																								 shape by delegating spill-state setup, capsule path resolution, syscall
																																																								 selection, and capsule posthook emission to focused helpers. The capped
																																																								 profile now shows `x64_native_program.oren` at about 43.4s total / 31.9s
																																																								 parse, with `_x64_emit_global_root_table_loop` exposed at about 74ms as the
																																																								 next parser body.
																																																								 X64 global-root table registration now separates root-offset data
																																																								 serialization, loop state creation, scratch initialization, loop header, and
																																																								 per-root registration step emission while preserving the one-table/one-loop
																																																								 runtime strategy. The capped profile now shows `x64_native_program.oren` at
																																																								 about 42.5s total / 31.2s parse, with `_emit_intrinsic_sys_windows_net_x64`
																																																								 exposed at about 71ms as the next parser body.
																																																								 Windows x64 net syscall dispatch now routes through focused family helpers for
																																																								 WSA bootstrap/close, IOCP, socket lifecycle, sockopt/shutdown, message I/O,
																																																								 and overlapped WSA operations while preserving the existing syscall match
																																																								 order. The capped profile now shows `x64_native_program.oren` at about
																																																								 42.6s total / 31.1s parse, with `_x64_classify_named_call_v0` exposed at
																																																								 about 97ms as the next parser body.
																																																								 X64 named-call classification now separates shadow-aware direct/import lookup,
																																																								 varargs fixed-arity metadata lookup, wrapper/self-recursion suppression, and
																																																								 direct-call arity validation while preserving the downstream call-info map
																																																								 contract. The capped profile now shows `x64_native_program.oren` at about
																																																								 43.2s total / 31.7s parse, with `_emit_intrinsic_sys_read_linux_x64` exposed
																																																								 at about 106ms as the next parser body.
																																																								 Linux x64 `sys_read` / `sys_write` lowering now shares fd/pointer/length spill
																																																								 state setup, capsule prehook dispatch, and syscall argument reload helpers
																																																								 while preserving read passthrough semantics and write's nonpositive-length
																																																								 zero return. The capped profile now shows `x64_native_program.oren` at about
																																																								 43.8s total / 32.3s parse, with `_compile_function_v0` exposed at about
																																																								 87ms as the next parser body.
																																																								 X64 function compilation now delegates function start/reset, ops analysis,
																																																								 frame preparation/header emission, function-state packing, and compile-option
																																																								 packing to focused helpers while keeping `_compile_function_v0` as a thin
																																																								 coordinator. The capped profile now shows `x64_native_program.oren` at about
																																																								 42.7s total / 31.1s parse, with
																																																								 `_emit_intrinsic_sys_cancel_io_ex_windows_x64` exposed at about 72ms as the
																																																								 next parser body.
																																																						     Serial/thread module
															     ASTBIN writes are now explicit prewarm work via
								     `OREN_MODULE_ASTBIN_CACHE_SERIAL_WRITE_MIN_MS`; `0` selects every parsed
									     module as a candidate and `false` disables serial-write candidates. Actual
									     serial ASTBIN writes stay opt-in behind
										     `OREN_MODULE_ASTBIN_CACHE_SERIAL_WRITE_ASTBIN=1` and now use a
										     module-specialized v2 ASTBIN writer with known-key traversal, one-pass
										     cached-pointer body emission, and `OREN_TRACE_ASTBIN_MODULE` phase
										     tracing. Forced prewarm is bounded by
									     `OREN_MODULE_ASTBIN_CACHE_SERIAL_WRITE_MAX_PARSE_MS` (default `250`;
									     `0`/`false` disables the parse-cost ceiling) plus the existing node budget.
									     Cache reads and fork-worker writes remain enabled, and explicit serial
									     prewarm now logs cache-write start/skip/encode/done phases. Module cache
									     directories still default to the compiler executable signature, and
									     controlled profiling runs can set
										     `OREN_MODULE_ASTBIN_CACHE_COMPILER_SIG` to reuse entries across stage2
											     rebuilds. `OREN_TRACE_ASTBIN_MODULE_SHAPES=1` prints the first bounded
											     full-vocabulary fallback map shapes for future module-writer profiling.
											     Focused no-artifact-cache proof: forced generator-import prewarm now writes
											     `std:result` in about 26ms, `std:time` in about 86ms, and `std:generator`
											     in about 247ms; the next process warm-hits all three with `cache_hit=1`
											     and `parse_ms=0`. Trait metadata maps are now covered by known-key
											     traversal instead of falling through to the full key vocabulary, so the
											     default parse budget remains a safety guard rather than a workaround for
											     these std modules. Capped full x64 self-host traces now complete module
								     parsing through `lib/compiler/compiler.oren`, finish the optimizer, and
								     reach x64 native emit. With direct string globals disabled,
									     `top_globals.user_slots` finishes in under a second; opt-in direct-string
									     probes now have direct string appends, slot counters, path/substep slow-slot
									     records, positive-only scalar fact metadata, and demand-driven data-constant
									     alias metadata, but compiler-shaped traces still show a per-slot direct
									     metadata/root bookkeeping cliff. The synthesized `__top_level__`
									     string-global assignment fast path now runs before generic expression
									     validation and local fact updates, so literal string globals bypass the
										     slow generic assignment path. Consecutive top-level string literal globals
										     now lower through a batched x64 op with direct encoded global-slot offsets,
										     reducing the compiler-shaped `__top_level__` statement count from 123 to
										     15. A no-slowtrace self-host probe confirmed the old per-item batch loop
										     still timed out inside `global_string_init_batch`, so the batch now emits
										     one compact runtime initializer loop over a `.data` table of
										     `{global_slot_off, cstr_off}` pairs instead of compiling one fixed store
										     sequence and two fixup maps per string. A focused 140-string x64 fixture
											     now records item-level offset/value/length/data substep progress. Full
											     self-host traces showed the compiler-shaped token-batch cliff was
											     encoded-offset lookup, so string batches now carry decoded slot offsets
												     with encoded offsets only as a fallback. Prebuilt string batch statements
												     now drop redundant per-item names/values/offsets/items payload after the
												     `.data` table is materialized, keeping `__top_level__` analysis/emission
												     on the compact table offset/count path. Empty list/map top-level globals
											     now batch by kind into runtime allocator loops over global-slot tables; a
											     compiler-shaped self-host probe reduced synthesized `__top_level__` body
											     emission from about 15.5s to about 5.5s and reaches
											     `x64.codegen.top.done`, making post-`__top_level__` x64 user-function
											     codegen throughput the next measured target. X64 local labels now use
											     compact internal keys instead of long function-derived prefixes; capped
											     self-host traces still stop after `x64.codegen.fns.start`, so the first
											     user-function emit path remains the measured bottleneck. X64 map/string-key
											     index get/set lowering now skips the generic list-dispatch body once
											     `recv_kind="map"` or a string literal key proves only map semantics are
											     reachable. This moved the first renamer hot function through all nested
											     AST string-key lookups and reduced it from roughly 136s to roughly 85s;
											     broader inferred string-field key kinds are intentionally not enabled
											     after a capped self-host probe produced a real `map: key is not a string`
												     panic. Map-only x64 index lowering now calls checked runtime map helpers
												     instead of emitting receiver tracking/kind/magic checks per access site.
												     The capped trace reduced `collect_toplevel_rename_pairs` further to
												     roughly 16s; parameter-map helpers such as `rename_lookup`, `scope_has`,
												     and larger `rename_stmt` codegen remain the next measured bottlenecks
												     because shared compiler source must still link in OBC builds without
												     native-only map helper calls. Compiler phase logs now append through
													     `oren_append_file` instead of reading and rewriting the entire log on
													     every phase, with matching C runtime and arm64/x64 native `O_APPEND`
													     support. A capped no-cache self-host trace now reaches
													     `link.optimizer.done`, global DCE, and `x64.codegen.ctx.done`; new
													     x64 runtime-object hash/cache/seed/build markers show the remaining
													     cold-cache gap is inside `x64.rtobj.build.start` before returning to
													     post-`__top_level__` user-function codegen throughput. X64 function
													     progress is now configurable with
													     `OREN_TRACE_X64_FNS_PROGRESS_INTERVAL`, and the renamer visitor pass
													     caches AST node type/child lookups plus loop lengths. Focused
													     no-cache traces reduced `collect_toplevel_rename_pairs` from the
													     prior roughly 16s to about 11.4s and `scope_push` from about 8.6s
													     to about 5.7s. Default optimizer phase logging now records aggregate
													     timings only and gates deep fold/list/const counters plus hot-function
													     rankings behind `OREN_TRACE_OPTIMIZER_DETAIL=1`; the optimizer
													     summary marker dropped from about 21s to about 2ms in a
													     compiler-shaped x64 trace. X64 string literal lowering now checks a
													     bounded 32-entry C-string MRU before the existing data dedup map, and
													     `rename_stmt` now uses independent early-return branches instead of a
													     nested `else if` chain. The same focused compiler-shaped trace reduced
													     `rename_stmt` from about 64.8s to about 12.1s and moved the active
													     diagnostic past `rename_expr`. X64 backend instruction emission now
													     calls `x64_core` builders directly instead of compiling a duplicate
													     prelude forwarding layer; the compiler-shaped trace reduced linked x64
													     functions from 2598 to 2501. X64 function frames now reserve dedicated
													     list/map literal spill slots only when a conservative ops scan finds
													     list/hash literals; focused frame probes show literal-free `__top_level__`
													     at `literal_slots=0` and list-literal `main` at `literal_slots=16`,
														     keeping the remaining active hotspot in real `x64_core`
														     instruction-builder/user-function emission. A low-register arithmetic
														     rewrite was rejected after parser and capped-trace evidence showed no safe
														     throughput win; capped traces can now opt into first-N user-function
														     phase detail with `OREN_TRACE_X64_FNS_DETAIL_LIMIT`. X64 call-depth hook
														     emission now uses structural runtime/no-call-depth metadata, direct fixed
														     `call rel32` byte appends, and compact enter/exit position lists patched
														     by ELF/PE emitters instead of per-hook generic fixup maps. Capped
														     diagnostics also proved that excessive per-function phase markers can
														     dominate the profile, so the next user-function work should keep tracing
														     bounded and coarse. `OREN_TRACE_X64_TOP_SLOW_FNS_LIVE=1` now emits
														     bounded live slow-function markers before timeout; the proof profile
														     captured `scope_push` at about 6.9s and `rename_stmt` at about 12.1s as
														     the next concrete x64 user-function targets. The renamer now uses
														     parent-linked scope frames instead of copying the whole scope stack on
														     push, `rename_expr` uses early-return branches, and shared child-traversal
							     helpers remove duplicated function body, statement-list, expression-list,
							     hash-pair, and type-field loops. Focused x64 probes moved `rename_stmt`
							     from about 199ms to 118ms and `rename_expr` from about 194ms to 66ms,
							     leaving the smaller dispatch checks as the remaining target.
							     Runtime-object code splice phase markers now separate code append,
							     compact function offsets, compact fixup metadata, legacy fixups, and
							     RIP-data labels. The focused x64 ELF fixture showed the splice itself
							     was fast, while call-depth hook patching and local fixups were paying
							     full runtime-function lookup-map materialization. Compact runtime
							     metadata now caches call-depth hook offsets directly, and ELF/PE
							     runtime helper lookup lazily caches only names requested by emitted
							     fixups. Focused evidence moved call-depth patching from roughly 5.4s
							     to about 7ms and generic local fixups from roughly 5.2s to about 106ms.
							     ELF/PE local-fixup dispatch now caches the fixup count and each
							     fixup kind once, with PE using single-branch dispatch instead of
							     testing every shape; the focused nested-map Linux x64 probe shows
							     local fixups at about 26ms, leaving runtime-object call replay and
							     broader user-function emission as the next measured x64 costs.
								     Runtime-object call-fixup replay now caches sidecar pointers/base
								     metadata once and reads u64 sidecars through a raw pointer helper,
								     moving the same 15,924-call focused replay from about 289ms to
								     about 237ms. X64 instruction builders now use explicit `low3`/`u8`
								     bit-mask helpers for ModRM/REX register packing and signed-byte
								     emission instead of routing those hot byte encodings through the
								     general positive modulo helper.
							     The refreshed Linux x64 self-host compile-only probe then exposed a
							     prerequisite seed-policy gap: missing `x64-linux/full` runtime-object
							     seeds were still cold-built by `oren_stage2` under the seed helper's
							     fixed 180s cap. The self-host compile-only gate now mirrors
							     `rtobj-seed-x64` by using stage1 as the bounded cold seed builder for
							     missing stage2-compatible x64 runtime-object seeds, with
							     `OREN_SELFHOST_RTOBJ_SEED_TIMEOUT_SECS` controlling that prerequisite
							     seed timeout. A follow-up capped probe now clears seed setup and reaches
							     x64 user-function emission; `rename_function_body` parameter traversal was
							     split into `rename_function_params`, moving the focused body marker from
							     roughly 4.9s to about 1.0s while params and statement-list traversal remain
							     the next renamer body-shape targets. The x64 main op-emitter loop now
							     caches the per-op dispatch kind and native gas-mode booleans instead of
							     repeatedly re-reading map/env state; a broader fast-`while` prefilter was
							     rejected because the capped self-host trace showed no material movement
							     in the first renamer slow markers. Bounded first-function detail tracing
							     now defaults to one summary append per function with prologue substep
								     fields, and x64 computes call-depth-default once per compile loop instead
								     of probing platform metadata in every user-function prologue. The proof
								     trace moved normal user-function depth-gate setup from roughly
								     970-1100ms to 0-5ms; remaining concrete x64 user-function work is the
								     actual body emission in `rename_function_params`, `rename_stmt_list`,
								     `rename_stmt`, and `rename_expr`. Statement/expression branch helpers
								     now reduce the focused renamer dispatch bodies: the latest x64 probe
								     shows `rename_stmt` around 61ms and `rename_expr` around 57ms, leaving
								     traversal helpers and annotation builtin checks as the next measured
									     renamer emit targets. Annotation builtin checks are now split by
									     category, replacing the former roughly 57ms monolithic checker with
									     about 20ms/15ms/15ms/6ms helper bodies; traversal helpers remain the
									     next focused renamer emit target. X64 base-memory and displacement
										     instruction builders now append ModRM/SIB/displacement bytes directly
										     through `_emit_mem_base_modrm_sib_disp` instead of allocating
											     per-instruction metadata maps; Linux/Windows x64 compile-only gates
											     cover the MOV, atomic, MOVDQU, and MOVDQA surface. X64 intrinsic-temp
											     sizing now includes the live spill slots held by array/hash literal
											     builders, with the nested-map literal fixture covered by the default
												     Linux/Windows x64 compile-only matrix. Shared byte-builder u16/u32
												     little-endian writes now mask signed values once instead of using
												     positive modulo per byte, with a focused signed-layout fixture covering
												     the negative-width path.
												     Renamer scope lookup now caches positive and negative answers per
												     parent-linked frame and updates the active frame cache on declaration;
												     `renamer_scope_cache_shadow_main` proves an imported alias can be
												     cached as absent, then shadowed correctly by a later local declaration.
												     X64 conditional branch and SETcc builders now decode condition names
												     through byte-based opcode helpers and central label/compare-not
												     emission uses direct numeric opcode builders, avoiding repeated
												     string-equality chains in hot branch lowering.
		     Host `rtobj-seed` now uses the same bounded stage1 build-compiler fallback
	     when a compatible stage2 runtime-hash seed is missing, so local NET/native
     matrix prewarm does not burn the verifier budget on repeated stage2 cold
     seed probes. The ARM64 Linux Docker NET leg still keeps the 10s stage1 hang
     guard, but uses a 900s stage2 cross-build floor because active self-hosted
     Linux NET/HTTP2 fixture compiles exceeded both the generic 120s stage2
     floor and a 300s trial on the primary dev host.
     Stage1 native quick now fails if a timeout-triggered retry was needed, and
     the retry enables `OREN_QI_TRACE=1` so hang symptoms leave fixture-boundary
     evidence in the preserved log.
   - AVM stdlib bundle policy: include portable pure/capability-backed stdlib modules
     by default, but expand through a manifest/size gate so bundle build time remains
     acceptable; keep host-only modules out until AVM shims exist.
   - Default AVM gate breadth now includes portable stdlib bytes/buffer views,
     u8 buffer iteration, checked integer casts, crypto hash vectors, iterator
     ranges, and Scene3D package assets.
   - Remaining required work: Note-side Swift UX integration, stderr or richer
     structured diagnostic capture if the Note UI needs it, larger multi-file
     compiler-in-AVM app suites, and CI coverage.
   - Gates: `make verify-libavm-ios` and `make verify-compiler-in-avm-ios-chain`.
   - Evidence: `project-doc/ios_avm_readiness_20260507.md`.
   - Stdlib OBC gate: `make verify-libavm-ios` now also runs
     `scripts/verify_avm_stdlib_obc_surface.sh`, which checks
     `tests/fixtures/avm_stdlib_obc_surface_manifest.json` against every import
     in `lib/std/stdlib_avm.oren`, rejects host-only exclusion leaks, generates
     the Oren smoke, and runs it against `build/plugins/stdlib_bundle.obc`.
     This prevents missing app-facing exports such as `STD_linalg_dot_f64` from
     reaching the iOS app.
   - SDK slices retained: `OrenAVMKit.xcframework` now provides deterministic and
     interactive configs, virtual FS/NET/PROC helpers, app file/directory mounts
     into VirtualFS, VFS export back to host files, live host-backed FS directory
     mounts for real app-owned file reads/writes during OBC execution, OBC run, stdout capture,
     verifier proof that interactive `std:time.sleep_ms` blocks the AVM worker on
     wall-clock time, an allowlisted `URLSession` prefetch bridge, and an
     interactive-default live NET callback for OBC `http.get(url).text()` /
     `http.get(url).bytes()` through `std:net/avm/http`
     backed by dynamic SDK enable/restrict/disable controls and a reusable SDK
     session, plus first `std:net/avm/socket.open/write/read/select/accept/close` TCP/UDP/WebSocket virtual
     session handles and `std:net/avm/tcp` / `std:net/avm/udp` convenience facades
     plus `std:net/avm/ws` over host-owned iOS sockets with readiness selection,
     pure `std:net/url` HTTP/WebSocket endpoint parsing shared by native and AVM-safe NET code,
     plus pure `std:sys` AVM capability-domain id/name/mask helpers,
     `std:env` capability-gated get/fallback/presence/truthy facade helpers,
     pure `std:path` slash-separated VFS/package path and traversal-safe root-join helpers,
     `std:fs` capability-gated text/byte/list-dir and root-scoped facade helpers,
     `std:proc` capability-gated run/status/result-combinator facade helpers,
     portable `std:timer` deadline/interval helpers and the native `std:avm/events`
     virtual event-bus facade over AVM `EVENT` domain and `std:avm/permission`
     facade and OPR0 permission mailbox for host-visible OBC permission intent,
     plus binary
     GFX frame and input mailboxes for OBC-published `std:ui` frames and
     host-injected pointer/resize/key/text events with Oren-side decoded
     `std:ui/avm.next_event()` maps, and a default UIKit/CoreGraphics
     `OrenAVMGraphicsView` renderer for the current `fill_rect`/`text`/
     `stroke_line`/`stroke_rect`/`circle`/`ellipse`/`polyline` subset, plus OBC-safe virtual DNS through
     `std:net/avm/dns` and the iOS live-NET resolver callback, and SDK-enforced
     live VNET session-count/per-session-byte limits, plus host-requested VM
     cancellation through the embed/iOS SDK APIs, plus an
     `OrenAVMPermissionGrantStore` that persists decoded permission decisions and
     reapplies live VNET allowed-host grants/revocations at runtime, plus reviewed
	     TCP listener/accept virtual sessions for OBC server flows, plus
	     host-enqueued FS/package lifecycle events through the AVM `EVENT` bus.
	     Remaining SDK work: visible permission prompt UX, compiler helper
     package, signed package-store support, and the game-grade GUI path:
     display-link pacing, retained resource handles, budget gates, low-latency
	     input ordering, Metal/`MTKView`, richer drawing ops, compact gamepad/controller
	     and coalesced motion events, focus records, and IME/composition records.
     The `OGF0` frame header now includes
     sequence/native-drawable/target-refresh metadata, and AVM validates `OGF0`
     frames plus `OGE0` host input/media-query events before accepting them. OBC
     can read host-populated screen attributes at runtime through
     `std:ui/avm.screen(0)` and can consume media-change events through the same
     virtual event channel: logical size, native drawable size, scale, target
     refresh, and host flags. Curated gates now
     cover malformed-frame rejection, op-count cap rejection, frame I/O-budget
     rejection, the host input queue depth cap, non-1000 resize scale propagation,
     latest-frame replacement/clear semantics, and FIFO pointer down/move/up
     ordering before mixed key/text events. Metal retained text now uses bounded
     SDK-side atlas packing plus same-atlas/scissor/opacity run coalescing so
     repeated and adjacent labels reduce texture churn and draw calls without
     changing the `OGF0` protocol. `make capture-ios-live-3d-performance`
     now builds the generated iPhoneOS live 3D capture app, runs its OBC program
     concurrently with `OrenAVMMetalView`, and republishes animated 3D frames from
     host `frame_tick` events; install/launch is opt-in via
     `OREN_IOS_LIVE_INSTALL=1` because it requires a provisioning profile that
     matches both the bundle ID and the target device. The target now writes
     `build/ios-live-3d/signing-preflight.json` and fails before the iOS build
     when install is requested with a missing or non-installable development
     profile. The 2026-06-27 `blu-ip` phone run installed and launched the
     generated app with Xcode's managed wildcard development profile, linked SDK
     categories through `-ObjC`, fixed Metal shader/CPU vertex stride matching
     through packed shader structs, and completed a 120-frame physically rotated
     cube mesh capture with stable normal-based lighting, phone-copied PNG
     snapshots, and 0 over-budget frames.
   - High-priority cleanup: remove legacy stdlib byte/string conversion paths from
     hot AVM app-facing APIs. Raw bytes should stay the performance path; text helpers
     may convert at the boundary but must not force list-of-byte round trips.
     Rolling API design now favors scoped objects and method chaining over
     root-level convenience helpers: NET uses `http.get(url).text()` /
     socket scopes, and codecs/bytes expose `"{}".json().text()`,
     `"a: 1\n".yaml().text()`, `cbor.cint(7).bytes().cbor()`, and
     `"hi".bytes().text()` through stdlib source and OBC metadata.
     Base64 and crypto hashes now follow the same rule with
     `"hi".bytes().base64()`, `"aGk=".base64_bytes().text()`,
     `"TWE".base64_url_bytes().text()`, and
     `bytes.from_string("abc").sha256_hex()` while keeping the byte hot
     path on exact-size `u8_buf` output; plain UI `text` frame commands now also
     write string bytes directly into OGF0 payloads, and UI color parsing reads
     hex digits directly from ASCII string bytes. SHA-1/SHA-256 digest inputs now read
     through shared byte views during virtual padding expansion, while digest outputs and native
     RNG bytes now write directly into fixed-size/result `u8_buf` buffers. HPACK
     plain literal decode now slices the header block directly, while Huffman
     decode trie storage uses unboxed `list_int` tables and Huffman
     string encode/decode, decoded-string boundaries, and full header-block
     encoding use exact-size `u8_buf` payloads or byte-slice conversion; TLS
     ALPN decoded-byte strings also convert through byte slices. HTTP/2 client
	     continuation/header-block and DATA response buffering now uses amortized
		     `u8_buf` accumulators, fragmented outbound HEADERS stream raw spans
		     across all CONTINUATION frames, inbound single-CONTINUATION header
		     blocks use the shared exact-capacity accumulator path, and PEM/Base64 body handling avoids
     materializing Oren byte lists with strict PEM body concatenation through raw
     exact-size writes; Base64/Base64URL encode hoists shared byte-view backing pointers once per call, and decode also rejects malformed padding and
			     nonzero trailing pad bits before returning exact-size `u8_buf` decoded bytes. `std:bytes`
							     now provides shared checked byte views plus explicit unchecked hot-loop u8/u32/i32/u64 little-endian readers, backing-aware u16/u32 plus unrolled u64 big-endian readers, signed checked byte-view helpers and public signed 64-bit endian getters that read `u8_buf` carriers directly after span validation, public 64-bit endian stores use unrolled direct `u8_buf` byte writes, `std:buffer` raw i64 stores use unrolled direct byte writes, CBOR/WebSocket 64-bit protocol headers use straight-line big-endian byte operations, compiler bytecode constants and ASTBIN u64 serializers use straight-line little-endian byte operations, x64 PE section-name headers emit exact eight-byte COFF names through straight-line literal bytes, x64 PE unused data directories plus import-thunk and export-name-pointer zero entries use shared zero-extension, ARM64/x64 ELF alignment padding uses shared zero-extension, compiler artifact whole-string append helpers use shared byte-builder string extension, ARM64 ELF and Mach-O runtime debug-record reserved u64 fields share straight-line zero helpers, ARM64 compiler fixed pointer-slot reservations use shared byte-builder zero-extension instead of byte-push loops, ARM64 Mach-O LC_UUID zero words emit straight-line, Mach-O fixed 16-byte name fields use shared zero-extension for padding, native whole-buffer/slice byte-to-string/u8-buffer conversions copy `u8_buf` carriers directly after one span check, `std:bytes.from_string`, `std:strings.to_bytes`, `std:ui/avm` plain text frame payloads, and `std:buffer` whole-string/string-slice u8 construction plus exact and offset-aware contiguous slice/dense-matrix string-slice and dense row-string copies route validated strings through byte-native runtime conversion, and AVM HTTP/WS text facades use whole-buffer byte-to-string conversion instead of repeated length-plus-slice conversion.
		     `std:strings` prefix/suffix/search/equality
			     and trim helpers plus JSON full decode/tag equality, CBOR canonical key ordering/text
					     encoding through growable `u8_buf` output plus hoisted shared `std:bytes` byte-view backing pointers for byte-string encode and
					     recursive/sequence decode header/additional-info reads, and full regex
     pattern/text matching now use direct string
     byte reads/slices. YAML comment stripping, quoted-scalar parse/escape,
     line/trim/key split, key sort, bare-identifier, prefix, and suffix helpers
     also avoid list-of-byte reconstruction, while XML/HTML parser literal
     matching, class-selector scans, DOM parsing, and streaming readers no
     longer allocate input byte lists for syntax tokens. WebSocket accept
     hashing now feeds SHA-1 directly from UTF-8 string bytes, native
     WebSocket byte send helpers use direct `u8_buf` length checks after type
     validation, 64-bit extended-length headers use straight-line big-endian stores,
     and header slices plus unmasked frame payloads copy with `oren_memcpy`;
     DNS QNAME labels and capsule NET IPv4 sockaddr reads/rewrites also copy
     through `oren_memcpy` after validation;
	     Base64/Base64URL
			     decode/encode writes exact-size output buffers directly, OGF0 frame byte payloads copy
				     directly from shared byte views with hoisted backing pointers, OGE0 event headers, payload lengths, and little-endian
					     payload fields read from hoisted shared byte-view backing pointers, UI command validation reads geometry/text-position/image-rect fixed-width payload fields through hoisted shared byte-view backing pointers, software rasterization reads geometry/text/image payload fields through hoisted shared byte-view backing pointers, Scene3D binary package magic/header/table reads and payload slices use hoisted shared byte-view backing pointers with explicit span guards, Metal batched image rects validate local draw/source
						     spans in one preflight pass before heap vertex allocation, CoreGraphics batched retained image rects preflight zero-size rects before retained image lookup, Metal/CoreGraphics retained 3D
							     draws skip sort/color work when clipping leaves no visible triangles,
								     fully transparent Metal draw-only plus retained mesh/model opcodes and
								     CoreGraphics draw-only opcodes skip vertex/texture/text-cache/lookup/depth-order work,
									     active empty-scissor/empty-clip spans skip Metal and CoreGraphics draw-only
												     opcodes before frame-prep or CGContext/resource/text draw work, Metal
												     full-frame clear shortcuts require unclipped, untranslated, fully opaque state
													     and skip duplicate leading fill vertices before prepared drawable work
											     plus unused pipeline binding when no prepared runs exist or no valid prepared run
												     reaches vertex binding, repeated same-scissor/texture/opacity Metal prepared runs skip redundant encoder state writes, failed Metal run/container allocation frees taken vertex bytes during flush, and failed growable vertex builders reset at continuing state-boundary flushes,
											     malformed zero-size/count-mismatched retained image/text draws reject before retained
											     resource lookup when the command is otherwise a no-op, Metal/CoreGraphics retained image/text/model uploads guard resource allocation before map insertion, Metal image/text appends report lazy run-array allocation failure, text-cache misses guard cache-key/cache-entry/run allocation before dictionary/glyph/vertex work, image-run constructors guard run allocation before vertex writes or exact heap allocation, prepared run arrays cap their initial frame-derived reservation, and Metal prepared-run coalescing preserves original run lists if the optional coalesced output array cannot be allocated, CoreGraphics truncated OGF0 payloads break traversal after restoring saved CGContext state, iOS GFX input event helpers reject oversized segmented/UTF-8 payloads before 16-bit length casts, immediate text opcodes reject empty/trailing-byte/invalid-UTF-8 payloads before attribute/texture preparation, retained text uploads reject empty payloads before map/string/resource work, and Metal/CoreGraphics zero-area
					     rectangles/circles/ellipses plus exact degenerate triangles skip before vertex/path work,
				     PPM header/body output, PPM RGBA encoding hoists validated byte-view
			     carrier/pointers once per call, and software-raster RGBA sampling
		     plus clear/pixel writes use raw exact-size buffer stores, and native `std:net/http`
     caches typed response body bytes for `.bytes()` on content-length and
     chunked responses. Native `oren_write_file` writes strings directly
     through syscalls without a transient byte list, and SHA-1/SHA-256 string
     hashing now reads UTF-8 string bytes directly for WebSocket accept values,
     Windows Schannel passphrase cache keys, and callers that already hold text;
     SHA-1/SHA-256 digest inputs read through shared byte views and digest buffers finalize through direct unchecked u8 stores
     after exact-size allocation, and native SHA-256 contiguous input remainders
	     copy with `oren_memcpy`; CoreGraphics/Metal retained 3D mesh painter
	     ordering grows raw order storage only for visible triangles beyond the inline stack buffer;
		    `std:bytes.to_hex` hoists direct u8-buffer data pointers once per call,
		    `std:bytes.concat` direct u8-buffer copies into fresh outputs, and
		    `std:bytes.copy_into` direct u8-buffer copies use
     bounded `oren_memcpy` for validated non-overlapping spans while fixtures
     cover both overlapping self-copy directions.
     Compiler source-policy
	     scans, scan-cache line/number parsing plus bounded load/save and delimiter writes, C-runtime include scanning,
		     compiler manifest JSON escaping, byte-native bytecode metadata payloads,
			     compiler-in-AVM VirtualFS fixture snapshots through exact-size AVMVFS01
			     `u8_buf` writes and byte-buffer body slices, OBC/OBX parse and link
			     loops use shared compiler-local byte views with overflow-safe span checks and guarded unchecked readers for u8 carriers, OBX
			     string/prefix encoding through compact byte builders, AST binary v1 full-value raw writes plus bounded u8 decode reads, bytecode string
     constants, native Mach-O/ELF object string payloads, runtime-object
     debug-name blobs, x64 native debug-table names, ARM64 native panic-message
     payloads, native runtime string concat/intern/slice copies, native capsule
     mount path resolution, realpath segment output, readdir names, and
     UNIX-socket path copies through `oren_memcpy`, shared compiler byte-builder
     append/list/string/set stores, C
     identifier escaping with raw exact-size output writes, raw u8/view/u8-matrix
     string copy helpers, `std:bytes.from_string`/`from_hex`, `std:strings` byte roundtrips,
	     `std:bytes` u8/endian writes with unrolled u64 `u8_buf` stores, unrolled `std:buffer` raw i64 stores for typed-buffer builders, straight-line CBOR/WebSocket u64 protocol byte operations, compiler bytecode/ASTBIN u64 serializer byte operations, x64 PE section-name literal byte plus data-directory/import-thunk/export-name-pointer zero emission, ARM64/x64 ELF alignment zero extension, compiler artifact whole-string byte-builder extension, ARM64 ELF/Mach-O runtime debug zero helpers, ARM64 compiler fixed pointer-slot zero extension, ARM64 Mach-O fixed UUID zero-word and 16-byte name padding emission, concat/copy u8-buffer spans, overlap-safe
	     u8 `copy_into`, `std:buffer` view/matrix `copy_from_bytes` direct
	     carrier reads through shared checked byte views with hoisted backing pointers for non-contiguous fallbacks,
     contiguous slice/dense-matrix byte/text exports, and
     raw u8-buffer load/store plus `copy_into` u8-buffer destinations, native byte-order writes,
     and `std:time` ISO-8601 UTC parsing now use direct source-string byte reads
     or exact-size/raw-pointer buffers too.
     Buffer views now expose wrapper objects over zero-copy slices,
     strides, and matrices, so callers can write `buf.slice(1, 3).text()` and
     `buf.matrix(2, 3).row(1).text()` without explicit local annotations
     instead of routing through root-level projection helpers.
     `make verify-stdlib-api-shape` now blocks known bad root-helper regressions:
     public fallible APIs should use the normal verb and return `value | oren_err`,
	     while syscall-style primitives use explicit `*_raw` names. The guard now covers
	     NET plus app-facing codec/parser/RNG helpers such as JSON/YAML/CBOR, Base64,
	     regex, PEM/X509, time parsing, crypto random bytes, HPACK/HTTP2 record
	     helpers, UI color/hex/PPM helpers, and `std:buffer` u8 view loads/stores.
     Native TCP/UDP/TLS/WebSocket and AVM virtual socket/TCP/UDP/WebSocket now
     follow the same session/object rule with examples like `conn.read_into(...)`,
     `socket.send_to(...)`, `conn.write_from(...)`, `conn.recv_text(...)`,
     `listener.accept(...)`, `session.recv_text(...)`, and
     `http2_client.new(...).request(...).text()`.
     XML/HTML follow the same rule with streaming readers first for large OBC
     payloads and DOM/query convenience on top. Native HTTP can use
     `response.html_reader()` / `response.html().find("title").text()`; AVM/OBC
     packages should opt into the parser explicitly and compose
     `response.text().html_reader()` to keep the default stdlib bundle inside
     iOS CompilerKit memory budgets.
     Design notes: `project-doc/ios_avm_sdk_design_20260531.md`,
     `project-doc/avm_ui_render_performance_design_20260531.md`.
   - Follow-up distribution design: after the GUI bridge gate, publish a curated
     signed OBC store repo with package manifests, hashes, capability declarations,
     and iOS download/verify/run flow. Register demo OBC packages there so the
     iOS app has useful downloadable examples once GUI/network gates are ready.
     The intended public store site is `store.hubstack.cn`, with PyPI-like
     release/discovery/download pages backed by the same signed index/package
     schema. The first Go service slice now exists as `cmd/obc-store-server` /
     `internal/obcstore`, with publisher/package/release publish, list/search,
     signed index, browser browse/detail/operator pages, download, and yank APIs.
     Write endpoints now accept an
     external-hash bearer token for deployment automation, while Basic Auth is
     retained for local bring-up. Publisher package/version/release writes now
	     accept publisher-scoped bearer tokens limited to that publisher id, with
	     JSON APIs for token rotation and revocation. Packages are public by default;
	     publisher/admin visibility changes can make a package private, which removes
	     it from public browse/search/index/download surfaces while retaining
	     authenticated owner/admin access.
	     `make verify-libavm-ios` starts the Go service, publishes a signed package
	     through the HTTP API with publisher-scoped auth, and proves iOS SDK
	     install/run from that service. The deterministic `.obc.zip` release bundle
	     format is now specified, emitted by demo tooling, accepted by the service,
	     served by release download APIs, advertised in `index.json`, and preferred
	     by the iOS SDK installer with expanded-artifact fallback. Operator status
		     now exposes deployment gates plus aggregate release-ready/incomplete counts,
		     missing bundle/source/signature/permission readiness counts, and data-dir
		     writable/storage byte totals by metadata/payload class, and
	     authenticated operator release lifecycle inventory
	     pages/APIs expose status/visibility/readiness filters, visibility,
	     readiness, latest-published state,
	     publish/yank/visibility action URLs, no-JS browser forms for those
		     release/package mutations, authenticated filterable update inventory page/API for
		     latest/superseded package versions by publisher/package/visibility/superseded state
		     with total/filtered counts, authenticated filterable append-only
		     audit page/API by action/actor/target with total/filtered counts, checked Traefik dynamic route
	     generation for the cloud-host backend, admin-env host fallback plus explicit
	     `sshpass -e` password mode for deployment, optional authenticated deploy-time
	     operator-status storage/readiness probes, public build-stamped health/status
	     metadata, a public live-route smoke target with strict build/release-readiness/operator-status modes, and a local data-dir backup/restore
	     smoke for metadata plus artifacts; live deployment replacement is currently
	     blocked by rejected SSH credentials for the configured admin host.
     Design note:
     `project-doc/obc_store_distribution_design_20260529.md`.
     Curated demo package sources now live under `examples/obc_store_demos/`;
     `make verify-obc-store-demos` builds and AVM-runs
     `oren-labs/science-calculator@0.1.0`, `oren-labs/ui-card-demo@0.1.0`,
     and `oren-labs/scene3d-asset-demo@0.1.0` package directories plus
     deterministic `.obc.zip` release bundles under `build/obc-store-demos`.
     Official demos bundle source as hashed package assets so host apps can
     show or ignore it, while store-only deterministic 640x360 PNG screenshots
     are published as release presentation metadata outside package manifests,
     client runtime assets, and bundles. Package detail pages render declared
     Oren source in-browser with syntax highlighting and an AST outline.
	     Scene3D package assets now include compact `boxes_xyz` cuboid authoring,
	     `prisms_xy` extruded polygon authoring, bounded `heightfields_xy` terrain grids,
		     bounded `surfaces_xyz` arbitrary surface grids, flat indexed `vertices_xy`, flat `triangles_xy`/`quads_xy`, flat per-triangle-color `triangles_xy_rgba`/`quads_xy_rgba`, rectangular `planes_xy`/`rects_xy`, filled `rounded_rects_xy`, flat `polygons_xy`,
		     regular `regular_polygons_xy`, `stars_xy`, circular `discs_xy`/`rings_xy`,
	     elliptical `ellipses_xy`/`ellipse_rings_xy`, thick `segments_xy`/`paths_xy`, sampled `beziers_xy`, partial `sectors_xy`/`arc_bands_xy`, sloped `ramps_xy`, solid `solid_ramps_xy`, post `posts_xy`, curb `curbs_xy`, multi-rail fence `fences_xy`, stepped `stairs_xy`, gable `gable_roofs_xy`, polygon-footprint `pyramids_xy`, vertical `walls_xy`, closed `rooms_xy`, and
	     glTF 2.0 JSON and GLB source lowering with URI/BIN buffers, sparse accessors, static `POSITION` and `COLOR_0` morph target weights, baked skinning through `JOINTS_n`/`WEIGHTS_n` and inverse bind matrices, sampled `gltf_animation` / `gltf_sample_time_milli` node translation/rotation/scale/morph-weight animations, material colors multiplied by `COLOR_0`, triangle/strip/fan topology, and explicit node or scene TRS/matrix hierarchy selection,
	     Wavefront OBJ, binary-or-ASCII STL source lowering, inline ASCII STL
	     text lowering, binary-or-ASCII PLY source lowering,
	     inline ASCII PLY text lowering, PLY face/vertex colors to `mesh3d_rgba`,
	     core 3MF ZIP mesh/build plus basematerial `displaycolor` lowering and
	     optional `3mf_triangle_set` subgroup selection,
	     package-authoring `scale_xyz_milli` pre-scaling, `pivot_xyz`, plus
	     `rotation_xyz_milli_deg` Euler rotation and `rotation_z_milli_deg`
	     shorthand, and `translation_xyz` for JSON coordinate and generated primitive meshes, plus
	     `cylinders_z`/`cones_z`/`spheres_xyz`/`ellipsoids_xyz`/`toruses_xyz`/`capsules_z` authoring that lower to existing
	     byte-native triangle mesh records for AVM/iOS without renderer ABI changes.
	     Procedural mesh packers are split into focused `std:ui/scene3d_shapes_flat`,
	     `std:ui/scene3d_shapes`, `std:ui/scene3d_shapes_arch`, and
	     `std:ui/scene3d_shapes_grid` helpers so broader package formats can
	     keep growing without pushing `std:ui/scene3d` or one shape helper toward
	     the source-line guardrail.
   - 2026-06-01: first `OrenAVMPackageStore` slices exist and are verified:
     manifest schema/ABI/hash validation, capability/budget/time config derivation,
     read-only package asset mounting into VirtualFS, package OBC run, HTTP
     `index.json` fetch, manifest hash verification, OBC download, declared asset
     download with SHA-256 verification, signed `index.json.sig` verification,
     trusted P-256 publisher signature verification, install, and run. Signature
     enforcement remains host policy: apps can require trust or let users accept
     unsigned/untrusted OBC risk. Persisted app-directory list/load/remove helpers
     are implemented and verified, with staged remote install before final path
     replacement. Explicit install policy is implemented and verified for signed-index
     downloads: replace, keep-existing, and fail-if-installed, including a signed
     `0.2.0` update fixture. Sibling Note handoff/verifier updates now check
     the staged signed package/trust SDK surface and expose visible update-status
     checks plus trusted package updates in the package manager (`../note` commit
     `86efc55`).
     The store service now exposes a package update-check endpoint that returns
     latest published release metadata plus `update_available`, and the iOS SDK
     exposes `OrenAVMPackageUpdateStatus` so host apps can query it from an
     installed package or explicit update URL before applying an install policy.
     Remote installs persist their source index URL inside SDK install metadata, so
     update checks can survive app relaunch without duplicating source-store state
     in each host app. The SDK can also install the latest trusted update from
     that persisted source metadata, and successful installed-package checks persist
     a last-known update status/check timestamp for offline host UI recovery.
	     Remaining package-store work is live deployment polish.
   - 2026-06-01: `scripts/issue_obc_store_trust.sh` and
     `make issue-obc-store-trust` issue store/publisher P-256 keys and host-app
     trust bundles into an external directory such as `../oren-ca/`; private keys
     remain outside this repo. The tool can include previous store public keys in
     the bundle for root rotation, and the service publishes the active index
     signing key id through signature headers and operator status.
     `OrenAVMOBCTrustBundle` now loads the generated JSON and feeds signed-index
     package downloads directly.

2. **AVM full-suite manifest coverage**
   - `make test-avm` now runs through `tests/avm/release_manifest.json`, which records
     fixture path, expected rc/error, env budgets, backend policy, deterministic mode,
     host-effect checks, and release-gate inclusion.
   - The manifest runner now supports multi-phase cases with per-phase env/args,
     cleanup, host-effect checks, line-prefix captures, and cross-phase assertions.
   - Nested multiverse AVM/VNET/VPROC/VFS fixtures and VFS inheritance are now
     release-gated with explicit setup builds and deny-default host policy.
   - Existing `tests/avm/test_*.oren` fixtures are now all present in the manifest;
     future work should add release metadata when new AVM fixtures are introduced.

3. **Cross-backend parity gates**
   - Expand only where current fixtures expose gaps.
   - Keep bytecode/C/native behavior aligned before adding new user-visible surfaces.
   - Verification should stay proportional to the touched surface: run focused
     feature/performance fixtures first, then the affected release or SDK gate.
     Avoid blanket platform sweeps unless ABI, packaging, or embedder code changed.

4. **Scientific stdlib math breadth**
   - Expand `std:math` toward C/C++ mathlib coverage without host-libm dependency.
   - Scalar `sqrt` keeps its deterministic eight-step Newton refinement as
     straight-line operations to reduce loop overhead in vector and matrix
     helper call sites.
   - Current retained surface includes `fmod`, IEEE-style nearest-even
     `remainder`, `remquo`, `modf`, integer rounding aliases
     `lround`/`llround`/`lrint`/`llrint`, `copysign`, public ties-to-even rounding aliases, `ilogb`/`logb`,
     `fdim`, `nextafter`/`nexttoward`, `pow` / `power` for integer, negative, fractional
     positive-base, infinity edge, and negative-base real-domain cases,
     `cbrt` with normal/subnormal/`fpclassify` classification and sign/non-finite coverage,
     tolerance predicates `isclose`/`isclose_abs`, finite `lerp`, range mapping helpers `inverse_lerp`, `remap`, and
     `remap_clamped`, graphics scalar/interpolation helpers `sign`, `step`,
     `fract`, `clamp`, `saturate`, `smoothstep`, and `smootherstep`,
     angle wrapping, shortest-angle delta, and shortest-path angle interpolation,
     pure finite `std:math/vec2` helpers including projection/rejection/reflection,
     pure finite `std:math/vec3` helpers including projection/rejection/reflection,
     pure finite `std:math/vec4` helpers including projection/rejection/reflection,
     pure finite `std:math/quat` helpers for axis-angle rotation, inverse, and interpolation,
     pure finite row-major `std:math/mat4` algebra, transform, normal-matrix, normal transform, model-view-projection composition, orthographic/frustum/perspective projection, screen project/unproject, validation, view, predicate, norm, inverse, projection, and transform helpers split through focused modules below the source-line guardrail, Frobenius/one/infinity norms and condition numbers, tolerance-aware affine/perspective predicates, and exact/tolerance-aware symmetric/upper-lower-triangular/diagonal/translation/scale/uniform-scale/invertible/singular predicates,
     overflow-aware `midpoint`,
     scaled two- and three-argument hypotenuse, cancellation-aware
     `expm1`/`log1p`, release-gated hyperbolic `sinh`, `cosh`, and `tanh`,
     inverse hyperbolic `asinh`, `acosh`, and `atanh`, plus release-gated
     `sin`, `cos`, `tan`, `atan`, `atan2`, `asin`, `acos`, and approximate
     real-valued `erf`/`erfc` bytecode coverage.
   - Gate app-visible additions through AVM bytecode fixtures first, then native/C parity.

5. **Native scheduler / green-task integration**
   - Keep syscall-first constraints and focused green/runtime gates.
   - Do not treat flake-only probes as retained work unless they improve a default gate.

6. **Reserve + unchecked push generalization**
   - Continue from measured optimizer/list-int evidence only.

## P2 / W3

1. **AVM allocation slabs, typed buffers, and list-int lowering**
   - Important for performance, but not sufficient for production iOS readiness without
     embedding/package/harness gates.

2. **Deterministic AVM scheduler maturity**
   - Continue budgeted child-universe scheduling and snapshot/restore work after the
     release harness can prove current behavior.

3. **Platform breadth**
   - Keep x64 Linux/Windows and arm64 Linux bring-up behind focused compile/runtime gates.

4. **Docs and source guardrails**
   - No source file should exceed 2000 lines; `make verify-source-line-guard`
     enforces this for tracked first-party source files.
   - Keep canonical docs concise; archive raw history in logs or focused project notes.

5. **Oren language tooling**
   - Build out `oren-lsp` and VS Code support for Oren syntax highlighting,
     diagnostics, completion, navigation, and code intelligence.
  - Current slices add a dependency-free Go JSON-RPC stdio language server with
    `initialize`/`shutdown`, full-document sync, deterministic bracket/string
    diagnostics plus parser-backed diagnostics on open/change, clean close
    handling, keyword/local-symbol completion, direct imported-module alias
    completion, typed struct/class field completion after proven receivers,
    and lexer-backed document symbols for imports, functions,
    variables, structs, and classes, same-file,
    opened-document cross-file, and import-resolved unopened-module definition
    navigation for relative and `std:` modules, plus lexer-backed hover and
    references over the same current/open/imported workspace graph with bounded
    transitive import traversal and cycle guards, scoped function-parameter and
    local-variable definition/hover/reference navigation with nested shadowing,
    constructor-inferred same-file and direct-import-alias struct/class field
    definition/hover/reference navigation with direct variable-alias propagation,
    direct named factory-return inference including `return if/else` expression branches plus factory-return field-chain evidence, direct typed constructor/factory
    expression receiver field navigation/completion plus constructor-field
    and constructor-bound variable/alias field-chain inference/completion, homogeneous list/hash indexed receiver evidence for field navigation and direct literal completions,
    list `for-in` loop element receiver evidence for field navigation/references and call-site parameter propagation,
    recursive nested constructor-bound call-site parameter and parameter-return field-chain inference including imported identity-return call sites,
    source-brace scoped local/list-for-in receiver completions inside function blocks,
    consistent direct call-site parameter inference with conflict
    invalidation, direct parameter-return propagation,
    consistent conditional branch return and assignment inference, unknown-assignment invalidation,
	    import document links, workspace symbol search across open/imported documents,
	    brace-based folding ranges, token/braced-block selection ranges, same-document document highlights for exact scoped locals/parameters,
	    import aliases, typed fields, and imported top-level symbols, and conservative prepare/rename workspace
	    edits for exact scoped parameters/local variables and same-document typed fields, plus
    full-document semantic-token classification for declarations/references/literals/operators and parser-derived
    parameter/property classes.
  - Current VS Code package slice adds the `.oren` language contribution, TextMate
    syntax grammar, language configuration, `vscode-languageclient` activation, and
    workspace-binary-or-PATH `oren-lsp` fallback with a smoke verifier for
    manifest/grammar/config/entrypoint integrity.
  - LSP/VS Code is now intentionally last-priority while Oren syntax and
    semantics keep rolling; prioritize language completeness and performance
    before bulk tooling expansion.
  - Remaining work is richer member inference beyond direct constructor/alias/factory-expression/factory-return-field-chain/constructed-field/constructor-bound-alias-field-chain/call-site/parameter-return/recursive-nested-call-site/imported-call-site-return/conditional-branch/return-if/indexed-container/list-for-in/scoped-completion evidence.

## Closed/Do-Not-Repeat Families

- Do not re-open Mach-O resolver variants based on generic Oren maps, global sorting,
  future-name rewrites, fixup-side sid lists, or nested bucket structures unless a new
  profile proves they beat the retained first-byte bucket resolver.
- Do not route task-group runtime policy validation through `std:task` helpers until the
  bytecode latency issue is removed.
- Do not treat runtime-native single-occurrence private helpers as dead code without
  stage2 plus fixture-build proof; runtime bundle/rooting can depend on non-textual
  reachability.
