# Native Backend Code Reuse Plan (ARM64 + x86_64)

Goal: treat **arm64** and **x86_64** as Tier-1 native targets while maximizing code reuse and keeping ABI correctness provable via fixtures.

This repo already has:

- A C backend that is architecture-neutral by construction (the host C compiler owns the ISA details).
- A native backend that emits machine code directly (arm64 is feature-rich; x86_64 is being brought up with fixtures).

To make native backends scale (and avoid duplicating semantics between arm64/x64), we need a shared structure:

## 1) Split responsibilities into three layers

### Layer A — Frontend lowering (shared)

Input: typed/linked AST.

Output: an architecture-neutral **NativeIR** (not bytecode; it stays close to “machine-like” ops).

Examples of NativeIR ops:

- `LoadLocal(slot)` / `StoreLocal(slot)`
- `ConstI32(n)`
- `AddI32`, `SubI32`, `MulI32`, `CmpI32(op)`
- `Jump(label)` / `JumpIfFalse(label)` / `Label(label)`
- `CallSym(name, argc)` (later: `CallIndirect`, closures)
- `Return`
- Runtime ops as explicit calls (`CallRuntime("oren_list_push", ...)`)

Key property: NativeIR encodes **semantics** (evaluation order, short-circuit rules, loop semantics), so backend authors don’t re-encode language rules per ISA.

### Layer B — ABI description (per target, shared interface)

Define a `NativeABI` interface with data tables + helpers:

- Register order for integer args
  - Linux x86_64 SysV: `edi, esi, edx, ecx, r8d, r9d` (ints)
  - Windows x64: `ecx, edx, r8d, r9d` + 32B shadow space
  - AArch64 (AAPCS64): `w0..w7` (ints)
- Stack alignment rules and prologue/epilogue requirements
- Caller/callee-saved registers
- Where return values live (typically `eax` / `w0`)

Codegen asks the ABI layer “where does arg i go?” instead of hardcoding per file.

### Layer C — Instruction selection + encoding (per ISA)

Take NativeIR + ABI and emit machine code:

- x86_64: use `lib/compiler/x64_core.oren` encoders + fixups
- arm64: use `lib/compiler/arm64_core.oren` encoders + fixups

This is where register allocation lives (even a simple stack-machine allocator can be shared at the IR level).

## 2) Why “args4” matters, even with varargs in the language

Varargs (`...rest`) is a **language-level feature**, but implementing it in native backends depends on:

- A correct fixed-arg ABI mapping first (including “extended” arg registers like `r8d/r9d` on Windows x64).
- A stable strategy for packing/rest arguments (typically into a `list`) and calling the underlying function or wrapper.
- Runtime/list support parity on the backend (to build the list deterministically).

So “args4” is not a goal by itself; it is a correctness milestone that proves our ABI layer handles the full register-arg set for Win64 and makes varargs implementation much less risky.

## 3) Near-term work items

1. Introduce `lib/compiler/native_abi.oren` interface + per-target implementations:
   - `lib/compiler/native_abi_x64_sysv.oren`
   - `lib/compiler/native_abi_x64_win64.oren`
   - `lib/compiler/native_abi_arm64_aapcs.oren`
2. Move current x64 ABI hardcoding to those tables (arg regs, shadow space, alignment).
3. Start extracting common lowering logic (statements/expressions) into a shared pass producing NativeIR, then hook it up to arm64 and x64 emitters.
4. Add fixtures that validate ABI-sensitive behavior (multi-arg, nested calls, spill correctness, alignment-sensitive calls).

