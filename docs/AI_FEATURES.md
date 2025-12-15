# Oren in the AI Era: Must-Have Features

As software engineering increasingly involves collaboration between humans and AI agents, a modern language must be designed for both **generation** (by LLMs) and **consumption** (by LLMs for context).

This doc focuses on language/tooling features. For VM/runtime execution requirements, see:

- `docs/AGENTIC_AI_TOP_FEATURES.md`
- `docs/AGENTIC_VM_KILLER_FEATURES.md`

## 1. Deterministic & Sandboxed Execution
AI agents often generate code that needs to be run immediately ("Code Interpreter" style).
*   **Feature:** A robust **WebAssembly (WASM)** backend or a restricted native runtime mode (`--sandbox`).
*   **Goal:** Allow agents to execute generated code safely without risking the host system.

Related AVM direction:
- Capability-scoped host calls: `docs/AVM_CAPABILITIES.md`
- Agentic VM killer features: `docs/AGENTIC_VM_KILLER_FEATURES.md`

## 2. Semantic Metadata (RAG-Ready)
LLMs rely on context. Traditional comments are often stripped or unstructured.
*   **Feature:** First-class **Documentation Comments** (`///`) that the compiler can export as structured **JSON** or **Markdown** alongside the binary.
*   **Goal:** Enable "Chat with your Codebase" systems to easily ingest function signatures, types, and docs without complex parsing.

## 3. Built-in Verification & Contracts
AI code generation is probabilistic and prone to subtle bugs.
*   **Feature:** First-class `test` blocks, `assert` keywords, and **Design-by-Contract** (pre/post-conditions).
*   **Goal:** Allow the AI to generate not just the implementation but also the *verification* logic, enabling self-correction loops (Generate -> Test -> Fix).

## 4. Machine-Readable Diagnostics (Stable Error Codes)
When agents build/patch code, they need to parse compiler errors without brittle string matching.

*   **Feature:** Stable compiler/VM error codes with structured payloads (span, hints, backtrace when applicable).
*   **Goal:** Enable “auto-fix” loops and reliable tooling integration.

## 4. Token Efficiency
Context windows are finite and expensive.
*   **Feature:** Concise syntax with strong **Type Inference**. Avoid boilerplate (like Java/C++ verbosity).
*   **Goal:** Fit more logic into the context window, improving the AI's ability to reason about complex systems.

## 5. Introspection & Reflection
AI agents are blind to runtime state without tools.
*   **Feature:** A simple, built-in mechanism to inspect the **AST** or **Runtime Types** of the program itself.
*   **Goal:** Allow an agent to "look around" the codebase programmatically to understand dependencies and structure.

## 6. High-Performance Concurrency (Chip Utilization)
Modern AI requires maximizing hardware utilization (CPU/GPU).
*   **Feature:** **Channels**, **Coroutines**, and **Pub/Sub** primitives (see `docs/CONCURRENCY_MODEL.md`).
*   **Goal:** Enable efficient data pipelines, parallel inference, and robust communication between agent components without low-level locking complexity.

## 7. Capability Governance (Least Privilege)
Agents will generate and run code that can be unsafe if unconstrained.
*   **Feature:** Capability-scoped native calls (FS/NET/PROC/TIME/CRYPTO/SIMD), with allow-lists and budgets.
*   **Goal:** Enable “self-healing” behavior: errors are recoverable, and unsafe actions are denied explicitly.

## 8. Reproducible Artifacts (Patch-Friendly Toolchain)
Agent workflows often require “minimize diff” patches and reproducible rebuilds.

*   **Feature:** Stable formatting + deterministic compiler output modes (where feasible) and content-addressed build artifacts (optional).
*   **Goal:** Make automated patching safer and reduce needless churn for RAG/indexing systems.
