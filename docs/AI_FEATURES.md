# Oren in the AI Era: Must-Have Features

As software engineering increasingly involves collaboration between humans and AI agents, a modern language must be designed for both **generation** (by LLMs) and **consumption** (by LLMs for context).

## 1. Deterministic & Sandboxed Execution
AI agents often generate code that needs to be run immediately ("Code Interpreter" style).
*   **Feature:** A robust **WebAssembly (WASM)** backend or a restricted native runtime mode (`--sandbox`).
*   **Goal:** Allow agents to execute generated code safely without risking the host system.

## 2. Semantic Metadata (RAG-Ready)
LLMs rely on context. Traditional comments are often stripped or unstructured.
*   **Feature:** First-class **Documentation Comments** (`///`) that the compiler can export as structured **JSON** or **Markdown** alongside the binary.
*   **Goal:** Enable "Chat with your Codebase" systems to easily ingest function signatures, types, and docs without complex parsing.

## 3. Built-in Verification & Contracts
AI code generation is probabilistic and prone to subtle bugs.
*   **Feature:** First-class `test` blocks, `assert` keywords, and **Design-by-Contract** (pre/post-conditions).
*   **Goal:** Allow the AI to generate not just the implementation but also the *verification* logic, enabling self-correction loops (Generate -> Test -> Fix).

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
