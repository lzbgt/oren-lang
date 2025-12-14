# Oren vs. Zig: Strategic Comparison

This document outlines the design philosophy of Oren by comparing it to Zig, highlighting intended advantages and acknowledging current trade-offs.

## Strategic Advantages

### 1. Hybrid Memory Management (Productivity vs. Control)
*   **Zig:** Enforces strict manual memory management (passing allocators). Excellent for systems control but adds friction for high-level logic.
*   **Oren:** Adopts a **"Dual Mode"** approach:
    *   **Default:** Optional Garbage Collection (Mark-and-Sweep) for high-level productivity (similar to Go/Python).
    *   **`--no-gc`**: A deterministic, manual mode where GC is compiled out entirely for embedded/real-time contexts.
    *   **Benefit:** Write business logic fast with GC; write drivers/hot-loops with zero overhead in the same language.

### 2. Zero-Dependency Native Toolchain
*   **Zig:** Relies on LLVM for release builds (massive dependency, slower compile times).
*   **Oren:** Uses a custom, hand-written native backend targeting Mach-O and ELF directly.
    *   **Benefit:** Instant edit-run cycles and a tiny compiler binary (~500KB vs Zig's ~100MB+), ideal for bootstrapping and distribution.

### 3. Native SIMD as a Primitive
*   **Zig:** Abstract SIMD via `@Vector`.
*   **Oren:** Exposes native hardware intrinsics (e.g., `simd_add_2d`, `simd_mul_4s` for ARM64 NEON) as first-class citizens.
    *   **Benefit:** Direct access to hardware acceleration for physics/graphics without fighting the optimizer.

### 4. "Script-like" Ergonomics
*   **Zig:** Explicit and verbose by design.
*   **Oren:** Python/Go-style syntax.
    *   **Benefit:** Lower cognitive load for tooling, build scripts, and UI logic.

---

## Disadvantages & Risks

### 1. Runtime Performance (The "Naive Backend" Cost)
*   **Zig:** LLVM backend produces world-class, optimized machine code.
*   **Oren:** Current native backend is a "Stack Machine" (pushes/pops to stack constantly) with no register allocator.
    *   **Impact:** Oren code is currently significantly slower (2x-10x) than optimized Zig/C.

### 2. Platform Limitations
*   **Zig:** Targets virtually every CPU and OS (x86, ARM, RISC-V, WASM, Windows).
*   **Oren:** Currently targets **ARM64 only** (macOS Apple Silicon and Linux ARM).
    *   **Impact:** Unusable on standard Windows/Intel desktops today.

### 3. Safety & Type Maturity
*   **Zig:** Strong spatial safety and robust compile-time checks.
*   **Oren:** "Conceptually static" but implementation is currently loose. The Garbage Collector is **conservative**, meaning it scans the stack guessing at pointers.
    *   **Impact:** Potential for memory leaks (integers mistaken for pointers) or crashes if type tags aren't respected.

### 4. The "Split Ecosystem" Risk
*   **Zig:** Unified ecosystem (allocator interface).
*   **Oren:** Supporting both GC and Manual modes risks fragmenting the library ecosystem (e.g., a "GC-only" JSON library causing leaks in a "No-GC" project).

### 5. Tooling Maturity
*   **Zig:** Robust build system, package manager, cross-compiler.
*   **Oren:** Bare-bones compiler.
    *   **Impact:** Users must currently implement basic I/O and networking from scratch; no debugger (DWARF) support.
