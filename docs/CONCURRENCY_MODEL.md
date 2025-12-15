# Oren Concurrency & IPC Model

To empower AI workloads and fully utilize modern multi-core chips, Oren provides a rich set of built-in concurrency primitives and communication patterns. This model prioritizes safety, efficiency, and ease of use, moving beyond raw OS threads to higher-level abstractions.

## Core Primitives

### 1. Lightweight Tasks (Coroutines)
*   **Concept:** Instead of heavy OS threads, Oren uses lightweight, runtime-managed tasks (green threads).
*   **Syntax (draft):** `spawn func(arg)` for OS threads (implemented today), and `yield`/task APIs for lightweight coroutines (planned).
*   **Implementation:** M:N scheduling (M tasks on N OS threads).
*   **Goal:** Allow millions of concurrent tasks (e.g., individual agent steps, network requests) with minimal overhead.

### 2. Channels (Sized & Unsized)
*   **Concept:** Typed, thread-safe pipes for passing data between tasks.
*   **Syntax (draft):** `chan<Type>(buffer_size)` (not implemented yet).
*   **Behavior:**
    *   **Unsized (0):** Synchronous rendezvous. Sender blocks until receiver is ready.
    *   **Sized (N):** Buffered. Sender blocks only when buffer is full. Provides backpressure.
*   **AI Use Case:** Streaming tokens from LLMs, pipelining data preprocessing, decoupling inference from ingestion.

### 3. Atomics & Memory Ordering
*   **Concept:** Low-level synchronization primitives for high-performance data structures.
*   **Features:** `atomic_add`, `atomic_cas` (Compare-And-Swap), `atomic_load`, `atomic_store`.
*   **Goal:** Enable lock-free queues and counters without the overhead of mutexes.

## Advanced Patterns (Built-in)

### 4. Pub/Sub & Fan-Out
*   **Concept:** One producer broadcasting to multiple consumers.
*   **Mechanism:** First-class support for "multicast channels" or topic-based subscription.
*   **Syntax (Draft):**
    ```oren
    var topic = pubsub.new()
    var sub1 = topic.subscribe()
    var sub2 = topic.subscribe()
    topic.publish(data) // sub1 and sub2 both receive data
    ```
*   **AI Use Case:** Broadcasting model weight updates, sending inference results to both a user UI and a logging service.

### 5. Structured Concurrency
*   **Concept:** Enforcing parent-child relationships for tasks.
*   **Mechanism:** `task_group` blocks. When a parent scope exits, it waits for (or cancels) all child tasks.
*   **Goal:** Prevent "orphaned" tasks and ensure clean resource shutdown (e.g., stopping all parallel searches if one result is found).

Agentic requirements (must-have):

*   **Cancellation propagation:** Child tasks inherit a cancellation token; parent cancellation cancels children.
*   **Deadlines/timeouts:** Deadlines are part of the task context, so “best-first” searches can cancel losers quickly.
*   **Supervision:** Prefer structured “supervisor” patterns for restart policies (optional, but high value for self-healing agents).

### 6. Parallel Iterators (Map-Reduce)
*   **Concept:** Data-parallelism made easy.
*   **Syntax:** `par_map(list, func)`, `par_reduce(list, func, init)`.
*   **AI Use Case:** Batch processing of embeddings, parallel evaluations of agent trajectories.

## Implementation Roadmap
1.  **Foundation:** Thread Registry & Atomics (Done/In-Progress).
2.  **OS Threads:** `spawn` intrinsic (Linux clone / macOS bsdthread).
3.  **Synchronization:** Mutexes and Condition Variables (using Atomics + Futex).
4.  **Communication:** Channels (on top of Mutexes + Ring Buffer).
5.  **Scheduler:** M:N Scheduler for Coroutines (stackless-first via `yield` lowering).
6.  **High-Level:** Pub/Sub and Parallel Iterators.

## Agentic VM Considerations (No-JIT, Self-Healing)

For AVM execution (interpreter-only environments), concurrency primitives must:

- support cancellation/timeouts (to stop work when a better plan exists)
- be compatible with snapshot/restore (pause and resume tasks)
- be compatible with capability gating (NET/PROC may be disabled)

See:

- `docs/AVM_SPEC_V1.md`
- `docs/AGENTIC_VM_KILLER_FEATURES.md`
